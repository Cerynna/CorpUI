--[[--------------------------------------------------------------------------
    CorpUI - module Marchand
    A l ouverture d un marchand :
      - reparation automatique de tout l equipement (si on a l or)
      - vente automatique des objets gris (qualite "mediocre")
    La vente se fait par petits paquets : le serveur refuse les ventes
    trop rapprochees. Elle s arrete des que le marchand est ferme.
    Le panneau porte aussi la section des reactifs (Reactifs.lua).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local BATCH, DELAY = 8, 0.25

local db
local merchantOpen = false
local queue = {}
local soldValue, soldCount = 0, 0

local function sellPrice(link)
    if not link then return 0 end
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not fn then return 0 end
    local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(fn, link)
    return (ok and price) or 0
end

local function repair()
    if not db.repair or not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end
    if GetMoney() < cost then
        ns.Say(string.format(L.SHOP_NO_MONEY, ns.FormatMoney(cost)))
        return
    end
    RepairAllItems()
    ns.Say(string.format(L.SHOP_REPAIRED, ns.FormatMoney(cost)))
end

local function finishSale()
    if soldCount > 0 then
        ns.Say(string.format(L.SHOP_SOLD, soldCount, ns.FormatMoney(soldValue)))
    end
    soldValue, soldCount = 0, 0
end

local function sellBatch()
    if not merchantOpen then wipe(queue) finishSale() return end
    for _ = 1, BATCH do
        local item = table.remove(queue, 1)
        if not item then break end
        -- la case peut avoir change depuis le releve
        local id, count, link, quality = ns.BagItem(item.bag, item.slot)
        if id == item.id and quality == 0 then
            ns.UseBagItem(item.bag, item.slot)
            soldCount = soldCount + 1
            soldValue = soldValue + sellPrice(link) * (count or 1)
        end
    end
    if #queue > 0 then
        C_Timer.After(DELAY, sellBatch)
    else
        finishSale()
    end
end

local function sellGrey()
    if not db.sellGrey then return end
    wipe(queue)
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, ns.BagSlots(bag) do
            local id, _, link, quality, noValue = ns.BagItem(bag, slot)
            if id and quality == 0 and not noValue and sellPrice(link) > 0 then
                table.insert(queue, { bag = bag, slot = slot, id = id })
            end
        end
    end
    if #queue > 0 then sellBatch() end
end

---------------------------------------------------------------------------
-- Fenetre d options
---------------------------------------------------------------------------

local win

-- Deux sections : reparation et ventes (ce module), puis les reactifs
-- (section fournie par Reactifs.lua, ns.ReagentsOptions)
local function buildWindow()
    ns.root.shopWin = ns.root.shopWin or { point = "CENTER", x = 0, y = 60 }
    win = ns.UI.Window("CorpUIShop", ns.TITLE .. " - " .. L.MOD_SHOP, ns.root.shopWin, 440, 100)
    local form = ns.UI.Form(win, -34)
    form:Header(L.SHOP_H_REPAIR)
    form:Check(L.SHOP_OPT_REPAIR, function() return db.repair end, function(v) db.repair = v end)
    form:Check(L.SHOP_OPT_SELL, function() return db.sellGrey end, function(v) db.sellGrey = v end)
    local y, reagentsShown = form.y, nil
    if ns.ReagentsOptions then
        form:Gap(4)
        y, reagentsShown = ns.ReagentsOptions(win, form.y)
    end
    win:SetHeight(math.floor(-y + 10))
    win:HookScript("OnShow", function()
        form:Refresh()
        if reagentsShown then reagentsShown() end
    end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end
-- /corp reactifs ouvre aussi ce panneau
ns.OpenShopOptions = toggle

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.shop = root.shop or {}
        db = root.shop
        if db.repair == nil then db.repair = true end
        if db.sellGrey == nil then db.sellGrey = true end
    elseif event == "MERCHANT_SHOW" and db then
        merchantOpen = true
        repair()
        sellGrey()
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "MERCHANT_SHOW", "MERCHANT_CLOSED" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "marchand",
    panelName = "CorpUIShop",
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
    title = function() return L.MOD_SHOP end,
    desc = function() return L.SHOP_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})
