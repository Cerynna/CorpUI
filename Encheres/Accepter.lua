--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : "Accepter" pose sur "Achat immediat"

    Option (active par defaut) : quand la confirmation d achat immediat d un
    objet s ouvre (fenetre de Blizzard StaticPopup "BUYOUT_AUCTION"), elle
    est placee de facon que son bouton Accepter tombe exactement sur le
    bouton "Achat immediat" de la fiche de l objet. On clique deux fois au
    meme endroit : Achat immediat, puis Accepter. Le prix reste affiche
    dans la fenetre, au-dessus du bouton.
    Rien n est clique a la place du joueur : chaque achat demande ses deux
    clics sur les boutons de Blizzard (ce client interdit aux addons
    d acheter, et CorpUI n y touche pas).
    Lecture seule de StaticPopup1..4 (.which, ButtonContainer.Button1) et
    du bouton de Blizzard ; seule ecriture : la position de la fenetre
    (ClearAllPoints / SetPoint), que Blizzard refait a chaque ouverture
    d une fenetre. Aucun crochet, aucun champ ecrit.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local AH = ns.AH

local issecret = issecretvalue or function() return false end
local num, field = AH.num, AH.field

local function buyOpts()
    local db = AH.DB()
    if not db then return nil end
    if type(db.buy) ~= "table" then db.buy = {} end
    if db.buy.atButton == nil then db.buy.atButton = true end
    return db.buy
end

-- bouton "Achat immediat" de la fiche d un objet (s il est a l ecran)
local function buyoutButton()
    local ahf = ns.AHFrame and ns.AHFrame()
    local btn = field(field(field(ahf, "ItemBuyFrame"), "BuyoutFrame"), "BuyoutButton")
    if AH.visible(btn) then return btn end
end

local function center(f)
    local ok, x, y = pcall(f.GetCenter, f)
    x, y = ok and num(x), ok and num(y)
    local okS, s = pcall(f.GetEffectiveScale, f)
    s = okS and num(s)
    if x and y and s and s > 0 then return x * s, y * s, s end
end

-- place la fenetre : son bouton Accepter au centre du bouton Achat immediat
local function place(dlg, btn)
    local b1 = field(field(dlg, "ButtonContainer"), "Button1")
    if type(b1) ~= "table" then return false end
    local dx, dy, ds = center(dlg)
    local ax, ay = center(b1)
    if not (dx and ax) then return false end
    -- ecart (en pixels d ecran) ramene a l echelle de la fenetre
    local ox, oy = (dx - ax) / ds, (dy - ay) / ds
    local ok = pcall(function()
        dlg:ClearAllPoints()
        dlg:SetPoint("CENTER", btn, "CENTER", ox, oy)
    end)
    return ok
end

-- deja posee sur le bouton ?
local function anchoredTo(dlg, btn)
    local ok, _, rel = pcall(dlg.GetPoint, dlg, 1)
    return ok and rel == btn
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
    local o = buyOpts()
    if not (o and o.atButton) then return end
    local btn
    for i = 1, 4 do
        local dlg = _G["StaticPopup" .. i]
        if AH.visible(dlg) then
            local which = field(dlg, "which")
            if not issecret(which) and which == "BUYOUT_AUCTION" then
                btn = btn or buyoutButton()
                if btn and not anchoredTo(dlg, btn) then place(dlg, btn) end
            end
        end
    end
end)

-- case dans le panneau /corp hv
ns.AHPanelHooks = ns.AHPanelHooks or {}
table.insert(ns.AHPanelHooks, function(panel, form)
    form:Header(L.ACC_SEC)
    form:Check(L.ACC_OPT, function() local o = buyOpts() return o and o.atButton end, function(v)
        local o = buyOpts()
        if o then o.atButton = v end
    end)
end)

-- banc d essai
AH._accept = { place = place, button = buyoutButton }
