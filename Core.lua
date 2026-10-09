--[[--------------------------------------------------------------------------
    CorpUI - socle commun
    Boite a outils en modules. Ce fichier ne fait rien de visible a lui
    seul : il fournit a tous les modules
      - le chat (ns.Say / ns.Chat)
      - les notifications internes (ns.Listen / ns.Changed)
      - la sauvegarde globale CorpUIDB (ns.root), chaque module
        gardant sa propre sous-table (CorpUIDB.buffs...)
      - le registre des modules et la commande /corp
      - le choix de la langue et le bouton de minicarte

    Ajouter un module : un dossier, ses fichiers dans le TOC, puis
      ns.RegisterModule({
          command = "mot",              -- /corp mot ...
          title   = function() ... end, -- nom affiche
          desc    = function() ... end, -- ligne d aide
          Slash   = function(input) ... end,
          Open    = function() ... end,  -- clic gauche sur la minicarte
          Alt     = function() ... end,  -- clic droit sur la minicarte
      })

    Regles de construction (contrainte des secret values de ce client) :
      - aucun hook sur une fonction de Blizzard
      - aucune ecriture sur une globale existante (seulement les notres)
      - aucun ajout dans UISpecialFrames
----------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
local L = ns.L

ns.VERSION = "1.0"
ns.TITLE = "|cffd65cffCorp|r|cffffd100UI|r"

-- Textures de CorpUI (dossier Media) : logo genere avec Nano Banana, barre lisse calculee
ns.MEDIA = "Interface\\AddOns\\CorpUI\\Media\\"
ns.LOGO = ns.MEDIA .. "logo64"
ns.BAR_TEXTURE = ns.MEDIA .. "statusbar"

-- Identite visuelle : obsidienne, cristal violet, filets d or.
-- Fond, bandeau et filigrane generes avec Nano Banana (Media/theme_*).
ns.FONT_HEAD = ns.MEDIA .. "xpbold.ttf"      -- Archivo Black (licence OFL)
ns.COLORS = {
    bg      = { 0.035, 0.03, 0.055 },
    panel   = { 0.075, 0.05, 0.11 },
    border  = { 0.30, 0.20, 0.42 },
    violet  = { 0.84, 0.36, 1.00 },
    gold    = { 1.00, 0.82, 0.25 },
    text    = { 0.86, 0.84, 0.90 },
}

-- Couleur d accent au choix (onglet General). Le liseré, les fonds et les
-- degrades en derivent ; l or reste l or. Appliquee a la lecture de la
-- sauvegarde, avant la construction des cadres : un changement demande un
-- rechargement de l interface.
ns.THEMES = {
    { key = "violet",  color = { 0.84, 0.36, 1.00 } },
    { key = "blue",    color = { 0.28, 0.56, 1.00 } },
    { key = "cyan",    color = { 0.20, 0.84, 0.90 } },
    { key = "green",   color = { 0.30, 0.88, 0.42 } },
    { key = "amber",   color = { 1.00, 0.58, 0.16 } },
    { key = "red",     color = { 1.00, 0.26, 0.30 } },
    { key = "pink",    color = { 1.00, 0.42, 0.76 } },
    { key = "silver",  color = { 0.76, 0.79, 0.86 } },
    -- sombre : anthracite et noir, accent gris neutre, images presque eteintes
    { key = "dark",    color = { 0.58, 0.60, 0.64 },
      border = { 0.20, 0.205, 0.22 }, panel = { 0.085, 0.085, 0.095 }, bg = { 0.025, 0.025, 0.028 },
      tint = { 0.34, 0.34, 0.36 } },
    { key = "class" },
}

local function themeDef(key)
    for _, t in ipairs(ns.THEMES) do
        if t.key == key then return t end
    end
end

function ns.ThemeColor(key)
    if key == "class" then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return { c.r, c.g, c.b } end
        key = "violet"
    end
    for _, t in ipairs(ns.THEMES) do
        if t.key == key and t.color then return t.color end
    end
    return ns.THEMES[1].color
end

local function applyTheme(key)
    -- style Moderne (09/10) : plat, liserés noirs, fonds neutres
    ns.MODERN = ns.root ~= nil and ns.root.style == "moderne"
    local a = ns.ThemeColor(key)
    local C = ns.COLORS
    C.violet = { a[1], a[2], a[3] }
    local def = themeDef(key)
    if def and def.border then
        C.border, C.panel, C.bg = def.border, def.panel, def.bg
    elseif key == "violet" or key == nil then
        C.border = { 0.30, 0.20, 0.42 }
        C.panel  = { 0.075, 0.05, 0.11 }
        C.bg     = { 0.035, 0.03, 0.055 }
    else
        C.border = { a[1] * 0.36, a[2] * 0.36, a[3] * 0.36 }
        C.panel  = { 0.02 + a[1] * 0.07, 0.02 + a[2] * 0.07, 0.02 + a[3] * 0.07 }
        C.bg     = { 0.025 + a[1] * 0.012, 0.025 + a[2] * 0.012, 0.025 + a[3] * 0.012 }
    end
    C.themeKey = key or "violet"
    C.tint = def and def.tint
    if ns.MODERN then
        C.border = { 0, 0, 0 }
        C.panel  = { 0.07, 0.075, 0.09 }
        C.bg     = { 0.035, 0.038, 0.047 }
        C.tint   = nil
    end
end
ns.ApplyTheme = applyTheme

-- Style de l interface : "classique" (violet, images du theme) ou
-- "moderne" (plat ; passe a la couleur de classe et a la police Saira, en
-- gardant les choix d avant pour un retour au classique). Applique au
-- prochain rechargement, comme la couleur du theme.
function ns.SetStyle(v)
    local db = ns.root
    if not db or (db.style or "classique") == v then return end
    if v == "moderne" then
        db.styleBackup = { theme = db.theme, font = db.font }
        db.theme, db.font = "class", "Saira"
    else
        local b = db.styleBackup
        if type(b) == "table" then db.theme, db.font = b.theme, b.font end
        db.styleBackup = nil
    end
    db.style = v
end

-- Les images du theme sont violettes : pour une autre couleur, on les
-- passe en gris puis on les teinte avec l accent ; style Moderne : retirees
function ns.TintThemeTexture(tex, strength)
    local C = ns.COLORS
    if ns.MODERN then
        tex:SetTexture(nil)
        return
    end
    if C.themeKey == "violet" then return end
    tex:SetDesaturated(true)
    if C.tint then tex:SetVertexColor(C.tint[1], C.tint[2], C.tint[3]) return end
    local k = strength or 1
    tex:SetVertexColor(0.5 + (C.violet[1] - 0.5) * k, 0.5 + (C.violet[2] - 0.5) * k, 0.5 + (C.violet[3] - 0.5) * k)
end
local CHAT_PREFIX = ns.TITLE .. ": "

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------

function ns.Chat(msg)
    local frame = DEFAULT_CHAT_FRAME or ChatFrame1
    if frame then frame:AddMessage(msg) end
end

function ns.Say(msg)
    ns.Chat(CHAT_PREFIX .. msg)
end

---------------------------------------------------------------------------
-- Outils communs aux modules
---------------------------------------------------------------------------

local issecret = issecretvalue or function() return false end

-- Personnage courant : "Nom-Royaume", cle des donnees par personnage
function ns.CharKey()
    local name = UnitName("player")
    local realm = GetRealmName and GetRealmName() or "?"
    return (name or "?") .. "-" .. (realm or "?")
end

---------------------------------------------------------------------------
-- Noms des autres joueurs (messages entre CorpUI, MP, groupe).
-- Ce client active les noms uniques regionaux (RegionalUniqueNamesEnabled ;
-- NameUtil et UnitPopupSharedUtil.GetFullPlayerName, branche forever) :
-- UnitName rend (prenom, nom de famille) et un joueur s ecrit
-- "Prenom Nom" (separateur espace, sans royaume) dans les evenements de
-- discussion, les MP et les menus de Blizzard. Sans ce mode : "Nom-Royaume".
-- Identite d un joueur = cette forme ; Sender y ramene les autres ecritures
-- ("Prenom-Nom", "Prenom Nom-Royaume", "Nom" seul sur notre royaume).
---------------------------------------------------------------------------

local issecretN = issecretvalue or function() return false end
local function plainString(v)
    if issecretN(v) or type(v) ~= "string" then return nil end
    return v
end

ns.Names = {}
local Names = ns.Names

function Names.Regional()
    if type(RegionalUniqueNamesEnabled) ~= "function" then return false end
    local ok, v = pcall(RegionalUniqueNamesEnabled)
    return ok and not issecretN(v) and v == true
end

-- royaume du joueur, sans espace (comme le serveur l ecrit)
local realmCache
function Names.Realm()
    if realmCache then return realmCache end
    local r
    if GetNormalizedRealmName then
        local ok, v = pcall(GetNormalizedRealmName)
        r = ok and plainString(v) or nil
    end
    if not r or r == "" then
        local ok, v = pcall(GetRealmName)
        v = ok and plainString(v) or nil
        r = v and (v:gsub("[%s%-]", "")) or nil
    end
    if r and r ~= "" then
        realmCache = r
        return r
    end
    return "?"
end

-- n importe quelle ecriture d un nom de joueur -> identite (nil si illisible)
function Names.Sender(raw)
    raw = plainString(raw)
    if not raw then return nil end
    raw = raw:match("^%s*(.-)%s*$")
    if raw == "" then return nil end
    if Names.Regional() then
        local first, rest = raw:match("^([^%s%-]+)[%s%-](.+)$")
        if not first then return raw end
        -- "Prenom Nom-Royaume" (ancienne ecriture de CorpUI) : royaume retire
        local realm = Names.Realm()
        if realm ~= "?" and #rest > #realm + 1 and rest:sub(-(#realm + 1)) == "-" .. realm then
            rest = rest:sub(1, -(#realm + 2))
        end
        return first .. " " .. rest
    end
    local n, r = raw:match("^([^%-]+)%-(.+)$")
    if n then
        r = r:gsub("%s", "")
        if r == "" then r = Names.Realm() end
        return n .. "-" .. r
    end
    return raw .. "-" .. Names.Realm()
end

-- identite d une unite ("player", "raid3"...)
function Names.Unit(unit)
    local ok, n, r = pcall(UnitName, unit)
    if not ok then return nil end
    n, r = plainString(n), plainString(r)
    if not n or n == "" or n == UNKNOWNOBJECT then return nil end
    if r and r ~= "" then
        if Names.Regional() then return Names.Sender(n .. " " .. r) end
        return Names.Sender(n .. "-" .. r)
    end
    return Names.Sender(n)
end

local meCache
function Names.Me()
    if meCache then return meCache end
    local v = Names.Unit("player")
    if v and (Names.Regional() or Names.Realm() ~= "?") then meCache = v end
    return v
end

-- destinataire d un MP (SendChatMessage, SendAddonMessage "WHISPER")
function Names.Whisper(id)
    id = plainString(id)
    if not id or Names.Regional() then return id end
    local n, r = id:match("^([^%-]+)%-(.+)$")
    if n and r == Names.Realm() then return n end
    return id
end

-- affichage : sans notre royaume ; court = prenom seul (lignes etroites)
function Names.Display(id)
    id = plainString(id) or "?"
    if Names.Regional() then return id end
    local n, r = id:match("^([^%-]+)%-(.+)$")
    if n and r == Names.Realm() then return n end
    return id
end

function Names.Short(id)
    id = plainString(id) or "?"
    if Names.Regional() then return id:match("^(%S+)") or id end
    return Names.Display(id)
end

-- abreviations de l argent en couleurs (textes MONEY_G/S/C : po pa pc en
-- francais), communes a tout CorpUI
function ns.MoneySymbols()
    return "|cffffd700" .. (L.MONEY_G or "g") .. "|r", "|cffc7c7cf" .. (L.MONEY_S or "s") .. "|r",
        "|cffeda55f" .. (L.MONEY_C or "c") .. "|r"
end

-- 123456 -> "12po 34pa 56pc" en couleurs
function ns.FormatMoney(copper)
    copper = math.floor(copper or 0)
    local G, S, Cu = ns.MoneySymbols()
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. G) end
    if s > 0 or g > 0 then table.insert(parts, s .. S) end
    table.insert(parts, c .. Cu)
    return table.concat(parts, " ")
end

-- Temps ecoule depuis un horodatage time() : "5 min", "3 h", "2 j"
function ns.FormatAgo(stamp)
    if not stamp then return "?" end
    local d = time() - stamp
    if d < 3600 then return string.format(L.AGO_MIN, math.max(1, math.floor(d / 60))) end
    if d < 86400 then return string.format(L.AGO_H, math.floor(d / 3600)) end
    return string.format(L.AGO_D, math.floor(d / 86400))
end

function ns.ItemName(id)
    if not id then return nil end
    local fn = (C_Item and C_Item.GetItemNameByID) or nil
    if fn then
        local ok, name = pcall(fn, id)
        if ok and name then return name end
    end
    if GetItemInfo then
        local ok, name = pcall(GetItemInfo, id)
        if ok and name then return name end
    end
    return nil
end

function ns.ItemIcon(id)
    local fn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if fn and id then
        local ok, tex = pcall(fn, id)
        if ok and tex then return tex end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Nombre dans les sacs (sans la banque)
function ns.ItemCount(id)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn or not id then return 0 end
    local ok, n = pcall(fn, id)
    if ok and n and not issecret(n) then return n end
    return 0
end

-- Sacs : API moderne C_Container, sinon l ancienne
-- Sacs du joueur : 0 a 4, puis le sac de composants (5) sur ce client
function ns.PlayerBags()
    local list = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do list[#list + 1] = bag end
    local reagent = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or ((NUM_BAG_SLOTS or 4) + 1)
    if reagent > (NUM_BAG_SLOTS or 4) then list[#list + 1] = reagent end
    return list
end

-- Premier sac de banque (apres le sac de composants)
function ns.FirstBankBag()
    if Enum and Enum.BagIndex and Enum.BagIndex.BankBag_1 then return Enum.BagIndex.BankBag_1 end
    return (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 1) + 1
end

function ns.BagSlots(bag)
    local fn = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if not fn then return 0 end
    local ok, n = pcall(fn, bag)
    return (ok and n) or 0
end

-- Renvoie itemID, quantite, lien, qualite, sansValeur ; nil si case vide
function ns.BagItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and info then
            return info.itemID, info.stackCount or 1, info.hyperlink, info.quality, info.hasNoValue
        end
        return nil
    end
    if GetContainerItemInfo then
        local ok, _, count, _, quality, _, _, link, _, noValue, id = pcall(GetContainerItemInfo, bag, slot)
        if ok and link then return id, count or 1, link, quality, noValue end
    end
    return nil
end

function ns.UseBagItem(bag, slot)
    local fn = (C_Container and C_Container.UseContainerItem) or UseContainerItem
    if fn then pcall(fn, bag, slot) end
end

-- Marchand ouvert : prix, taille du lot, stock (-1 : illimite, 0 : epuise),
-- cout etendu (jetons, objets, monnaie) et "achetable" d un objet. API
-- moderne (C_MerchantFrame.GetItemInfo, une table) sinon l ancienne
function ns.MerchantInfo(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
        if ok and type(info) == "table" then
            return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost, info.isPurchasable
        end
    end
    if GetMerchantItemInfo then
        local ok, _, _, price, quantity, numAvailable, isPurchasable, _, extendedCost = pcall(GetMerchantItemInfo, i)
        if ok then return price, quantity, numAvailable, extendedCost, isPurchasable end
    end
end

-- Depenses engagees chez le marchand, communes a tous les appels de
-- ns.MerchantBuy : GetMoney ne baisse qu au retour du serveur, et Reactifs
-- puis Metiers achetent au meme instant. Oubliees 5 s apres le dernier achat.
local merchantLedger = { base = 0, spent = 0 }
local function merchantPurse()
    local money = GetMoney and GetMoney()
    if issecret(money) or type(money) ~= "number" then return 0 end
    local lg = merchantLedger
    if not lg.at or GetTime() - lg.at > 5 then lg.base, lg.spent, lg.at = money, 0, nil end
    return math.min(money, lg.base - lg.spent)
end

local function merchantNum(v)
    if issecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- Achat chez le marchand ouvert (Reactifs, Metiers). needOf(itemID) donne
-- la quantite a acheter (nil ou <= 0 : rien). Lots fixes, stock limite et
-- bourse respectes. Jamais d achat sans confirmation de ce que Blizzard
-- fait confirmer : objet paye en jetons, en objets ou en monnaie ; ni d un
-- objet gratuit, epuise ou non achetable (ceux-la sont rendus a part).
-- Renvoie { { id =, n = } }, la somme depensee et { itemID } laisses.
function ns.MerchantBuy(needOf)
    local bought, spent, skipped = {}, 0, {}
    if not GetMerchantNumItems or not BuyMerchantItem then return bought, spent, skipped end
    for i = 1, merchantNum(GetMerchantNumItems()) or 0 do
        local id = GetMerchantItemID and merchantNum(GetMerchantItemID(i))
        local need = id and merchantNum(needOf(id))
        if need and need > 0 then
            local price, quantity, numAvailable, extended, purchasable = ns.MerchantInfo(i)
            price, quantity, numAvailable = merchantNum(price) or 0, merchantNum(quantity), merchantNum(numAvailable)
            local costItems = 0
            if GetMerchantItemCostInfo then
                local ok, n = pcall(GetMerchantItemCostInfo, i)
                costItems = (ok and merchantNum(n)) or 0
            end
            if issecret(extended) or extended == true or costItems > 0 or price <= 0
               or issecret(purchasable) or purchasable == false or numAvailable == 0 then
                skipped[#skipped + 1] = id
            else
                quantity = (quantity and quantity > 0) and quantity or 1
                local unit = price / quantity
                local purse = merchantPurse()
                local got = 0
                if quantity > 1 then
                    -- lots fixes : autant de lots que le besoin, la bourse et le
                    -- stock (-1 : illimite) le permettent
                    local lots = math.min(math.ceil(need / quantity), math.floor(purse / price))
                    if numAvailable and numAvailable > 0 then lots = math.min(lots, numAvailable) end
                    for _ = 1, lots do BuyMerchantItem(i, 1) end
                    got = math.max(0, lots) * quantity
                else
                    need = math.min(need, math.floor(purse / unit))
                    if numAvailable and numAvailable > 0 then need = math.min(need, numAvailable) end
                    local maxStack = GetMerchantItemMaxStack and merchantNum(GetMerchantItemMaxStack(i))
                    if not maxStack or maxStack < 1 then maxStack = 20 end
                    while need > 0 do
                        local n = math.min(need, maxStack)
                        BuyMerchantItem(i, n)
                        got = got + n
                        need = need - n
                    end
                end
                if got > 0 then
                    local cost = got * unit
                    spent = spent + cost
                    merchantLedger.spent = merchantLedger.spent + cost
                    merchantLedger.at = GetTime()
                    table.insert(bought, { id = id, n = got })
                end
            end
        end
    end
    return bought, spent, skipped
end

-- Nom d objet tire d un lien "|Hitem:...|h[Nom]|h"
function ns.LinkName(link)
    return link and link:match("%[(.-)%]")
end

---------------------------------------------------------------------------
-- Interface commune : infobulle, fenetres, boutons, positions
---------------------------------------------------------------------------

-- Infobulle privee : on ne touche pas au GameTooltip partage
local tip
function ns.Tooltip(owner, anchor)
    if not tip then
        tip = CreateFrame("GameTooltip", "CorpUITooltip", UIParent, "GameTooltipTemplate")
    end
    tip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    return tip
end

function ns.HideTooltip()
    if tip then tip:Hide() end
end

-- Position ancree par le coin haut-gauche : quand la hauteur change,
-- le haut ne bouge pas.
-- store.rel == "BOTTOMLEFT" : x, y = gauche et haut du cadre dans UIParent.
-- Sinon ancienne position (point, x, y par rapport au meme point d UIParent).
function ns.ApplyPos(frame, store)
    frame:ClearAllPoints()
    if store.rel == "BOTTOMLEFT" then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", store.x, store.y)
    else
        frame:SetPoint(store.point or "CENTER", UIParent, store.point or "CENTER", store.x or 0, store.y or 0)
    end
end

-- Fige la position actuelle sur le coin haut-gauche. A appeler cadre
-- affiche et avant de changer sa taille. force : meme si deja converti.
function ns.PinTop(frame, store, force)
    if store.rel == "BOTTOMLEFT" and not force then return end
    local l, t = frame:GetLeft(), frame:GetTop()
    if not l or not t then return end
    store.point, store.rel, store.x, store.y = "TOPLEFT", "BOTTOMLEFT", l, t
    ns.ApplyPos(frame, store)
    -- c est nous qui gardons la position, pas le cache de disposition du client
    if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
end

ns.UI = {}

local W8 = "Interface\\Buttons\\WHITE8X8"
local C = ns.COLORS

-- Degrade (API du client moderne), sinon couleur unie ; style Moderne :
-- toujours a plat (moyenne des deux bouts)
function ns.UI.Gradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetTexture(W8)
    if ns.MODERN then
        tex:SetColorTexture((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2)
        return
    end
    local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    if not ok then tex:SetColorTexture(r1, g1, b1, (a1 + a2) / 2) end
end

-- Police des titres (Archivo Black), repli sur celle du jeu
function ns.UI.HeadFont(fs, size)
    -- titres : variante grasse de la police choisie (Polices.lua), sinon Archivo
    local head = (ns.FontFile and ns.FontFile("black")) or ns.FONT_HEAD
    if not pcall(fs.SetFont, fs, head, size, "") or not fs:GetFont() then
        fs:SetFont("Fonts\\FRIZQT__.TTF", size, "")
    end
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
end

-- Fond plat : obsidienne, liseré violet de 1 px
function ns.UI.SetBackdrop(f, alpha)
    if not f.SetBackdrop then return end
    f:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    f:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], alpha or 0.92)
    f:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
end

-- Ombre portee douce autour d un cadre
function ns.UI.Shadow(f, size)
    size = size or 4
    for i = 1, size do
        local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetPoint("TOPLEFT", -i, i)
        t:SetPoint("BOTTOMRIGHT", i, -i)
        t:SetColorTexture(0, 0, 0, 0.16)
    end
end

-- Panneau d un module dans la fenetre principale. (Le nom et la signature
-- datent de l epoque ou chaque module avait sa fenetre : store est ignore.)
-- Afficher un panneau : ns.ShowPanel(panneau).
function ns.UI.Window(name, title, store, width, height)
    return ns.NewPanel(name, title, width, height)
end

-- Habillage des cadres de jeu (unites, barres, minicarte...) : fond
-- obsidienne, liseré violet de 1 px, ombre douce en option.
-- f.cuiBorder : la texture du liseré, a recolorer (combat, debuff...).
function ns.UI.Skin(f, alpha, shadow)
    local b = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    b:SetPoint("TOPLEFT", -1, 1)
    b:SetPoint("BOTTOMRIGHT", 1, -1)
    b:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], alpha or 0.9)
    if shadow then
        for i = 2, 4 do
            local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
            t:SetPoint("TOPLEFT", -i, i)
            t:SetPoint("BOTTOMRIGHT", i, -i)
            t:SetColorTexture(0, 0, 0, 0.18)
        end
    end
    f.cuiBorder, f.cuiBg = b, bg
    return b, bg
end

-- Remet le liseré a la couleur du theme
function ns.UI.ResetBorder(f)
    if f.cuiBorder then f.cuiBorder:SetColorTexture(C.border[1], C.border[2], C.border[3], 1) end
end

local function borderColor(f, c, a)
    if f.SetBackdropBorderColor then f:SetBackdropBorderColor(c[1], c[2], c[3], a or 1) end
end

-- Bouton plat : fond violet sombre, liseré qui passe a l or au survol
function ns.UI.Button(parent, text, width, onClick, template)
    local b = CreateFrame("Button", nil, parent, template and (template .. ",BackdropTemplate") or "BackdropTemplate")
    b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    b:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 0.95)
    borderColor(b, C.border)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    b.cuiText = fs
    b:SetNormalFontObject("GameFontHighlight")
    b:SetHighlightFontObject("GameFontHighlight")
    b:SetDisabledFontObject("GameFontDisable")
    b:SetPushedTextOffset(1, -1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    ns.UI.Gradient(hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.05, C.violet[1], C.violet[2], C.violet[3], 0.28)
    b:HookScript("OnEnter", function(self) if self:IsEnabled() then borderColor(self, C.gold) end end)
    b:HookScript("OnLeave", function(self) borderColor(self, C.border) end)
    b:SetText(text)
    b:SetSize(math.max(width, fs:GetStringWidth() + 20), 22)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

---------------------------------------------------------------------------
-- Widgets d options : liste deroulante, curseur + saisie, formulaire
---------------------------------------------------------------------------

-- libelle d un format "Largeur : %d" -> "Largeur" (la valeur est dans la saisie)
local function labelOf(fmt)
    -- deux-points pleine chasse (chinois) : 3 octets, a ramener a ":" avant
    -- les motifs (une classe [] de Lua compare des octets, pas des caracteres)
    local t = fmt:gsub("：", ":")
    t = t:gsub("%s*:%s*%%[%d%.]*[dfs]%s*%%%%", "")
    t = t:gsub("%s*:%s*%%[%d%.]*[dfs]", "")
    t = t:gsub("%s*%%[%d%.]*[dfs]", "")
    return t
end
ns.UI.LabelOf = labelOf

-- Liste deroulante CorpUI (un seul menu partage, ferme au clic ailleurs).
-- options() : liste de { value = , text = } ; get() / set(value)
local menu
local function openMenu(owner, options, get, set, after)
    if not menu then
        menu = CreateFrame("Frame", "CorpUISelectMenu", UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetClampedToScreen(true)
        ns.UI.SetBackdrop(menu, 0.98)
        menu.items = {}
        menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
        menu:SetScript("OnEvent", function(self)
            if self:IsShown() and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
                self:Hide()
            end
        end)
        menu:Hide()
    end
    if menu:IsShown() and menu.owner == owner then menu:Hide() return end
    menu.owner = owner
    local list = options()
    local w = math.max(owner:GetWidth(), list.width or 0, 120)
    -- liste longue : en colonnes de 20 lignes au plus (le menu ne defile pas)
    local per = #list
    if per > 20 then per = math.ceil(#list / math.ceil(#list / 20)) end
    local cols = math.max(1, math.ceil(#list / math.max(1, per)))
    for i, o in ipairs(list) do
        local it = menu.items[i]
        if not it then
            it = CreateFrame("Button", nil, menu)
            it:SetHeight(20)
            it.text = it:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            it.text:SetPoint("LEFT", 8, 0)
            it.text:SetPoint("RIGHT", -8, 0)
            it.text:SetJustifyH("LEFT")
            it.text:SetWordWrap(false)
            local hl = it:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.4, C.violet[1], C.violet[2], C.violet[3], 0.05)
            it.hl = hl
            menu.items[i] = it
        end
        it:ClearAllPoints()
        local col, row = math.floor((i - 1) / per), (i - 1) % per
        it:SetPoint("TOPLEFT", menu, "TOPLEFT", 1 + col * w, -1 - row * 20)
        it:SetWidth(w - 2)
        it.text:SetText(o.text)
        if o.title or o.value == get() then it.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) else it.text:SetTextColor(1, 1, 1) end
        -- o.title : en-tete inerte (pas de surbrillance, un clic ne fait rien)
        it.hl:SetShown(not o.title)
        if o.title then
            it:SetScript("OnClick", nil)
        else
            it:SetScript("OnClick", function()
                menu:Hide()
                set(o.value)
                if after then after() end
            end)
        end
        it:Show()
    end
    for i = #list + 1, #menu.items do menu.items[i]:Hide() end
    menu:SetSize(cols * w, per * 20 + 2)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    menu:Show()
end

-- menu a choix sous un bouton (options() : { {value, text}, ..., width = mini })
ns.UI.OpenMenu = openMenu

function ns.UI.Select(parent, width, options, get, set, after)
    local b = ns.UI.Button(parent, "", width)
    b:SetSize(width, 22)
    local fs = b.cuiText
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", 8, 0)
    fs:SetPoint("RIGHT", -20, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)    -- une seule ligne, coupee si trop longue
    -- chevron d or
    for i, rot in ipairs({ -math.pi / 4, math.pi / 4 }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetSize(6, 2)
        t:SetPoint("RIGHT", b, "RIGHT", i == 1 and -11 or -7, 0)
        t:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        pcall(t.SetRotation, t, rot)
    end
    b:SetScript("OnClick", function(self) openMenu(self, options, get, set, after) end)
    function b:Refresh()
        local v = get()
        for _, o in ipairs(options()) do
            if o.value == v then self:SetText(o.text) return end
        end
        self:SetText(tostring(v))
    end
    return b
end

-- Curseur CorpUI + saisie entouree de - / + (Maj : pas de 5)
function ns.UI.Slider(parent, width, lo, hi, step, get, set, after)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 20)
    local decimals = step < 1 and 1 or 0
    local function fmt(v) return decimals > 0 and string.format("%.1f", v) or tostring(math.floor(v + 0.5)) end
    local function apply(v)
        v = math.max(lo, math.min(hi, math.floor(v / step + 0.5) * step))
        v = math.floor(v * 100 + 0.5) / 100
        if v ~= get() then
            set(v)
            if after then after() end
        end
        f:Refresh()
    end
    local plus = ns.UI.Button(f, "+", 20, function() apply(get() + step * (IsShiftKeyDown() and 5 or 1)) end)
    plus:SetSize(20, 20)
    plus:SetPoint("RIGHT")
    local edit = CreateFrame("EditBox", nil, f)
    edit:SetSize(42, 20)
    edit:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetJustifyH("CENTER")
    edit:SetMaxLetters(6)
    ns.UI.Skin(edit, 0.8)
    edit:SetScript("OnEnterPressed", function(self)
        -- (parentheses : gsub renvoie aussi un compte, qui serait pris pour la base)
        local v = tonumber(((self:GetText() or ""):gsub(",", ".")))
        self:ClearFocus()
        if v then apply(v) else f:Refresh() end
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() f:Refresh() end)
    edit:SetScript("OnEditFocusLost", function() f:Refresh() end)
    local minus = ns.UI.Button(f, "-", 20, function() apply(get() - step * (IsShiftKeyDown() and 5 or 1)) end)
    minus:SetSize(20, 20)
    minus:SetPoint("RIGHT", edit, "LEFT", -2, 0)

    local s = CreateFrame("Slider", nil, f)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("LEFT", 2, 0)
    s:SetPoint("RIGHT", minus, "LEFT", -8, 0)
    s:SetHeight(14)
    s:SetHitRectInsets(0, 0, -4, -4)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    pcall(s.SetObeyStepsOnDrag, s, true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(0, 0, 0, 0.65)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(6, 14)
    thumb:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    s:SetThumbTexture(thumb)
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetHeight(4)
    ns.UI.Gradient(fill, "HORIZONTAL", C.violet[1] * 0.5, C.violet[2] * 0.5, C.violet[3] * 0.5, 1, C.violet[1], C.violet[2], C.violet[3], 1)
    local syncing = false
    s:SetScript("OnValueChanged", function(_, v, user)
        if syncing or user == false then return end
        apply(v)
    end)
    function f:Refresh()
        local v = get()
        syncing = true
        s:SetValue(v)
        syncing = false
        if not edit:HasFocus() then edit:SetText(fmt(v)) end
    end
    f.slider, f.edit = s, edit
    return f
end

-- Formulaire d options : intertitres, cases, curseurs, listes, sur une ou
-- plusieurs colonnes (form:Columns). Chaque element se place a la hauteur
-- courante (form.y) ; onChange est appele apres chaque modification, puis
-- tout le formulaire est relu (form:Refresh, a lancer aussi a l affichage).
function ns.UI.Form(parent, y, onChange, width)
    local form = { y = y or -34, refreshers = {}, width = width or 440, col = 0, rowH = 0 }
    function form:Refresh() for _, r in ipairs(self.refreshers) do r() end end
    local function changed()
        if onChange then onChange() end
        form:Refresh()
    end
    form.Changed = changed
    -- colonnes : les elements suivants se rangent n par ligne
    function form:Columns(n)
        self:EndColumns()
        self.cols = n
    end
    function form:EndColumns()
        if self.col > 0 then self.y = self.y - self.rowH end
        self.cols, self.col, self.rowH = nil, 0, 0
    end
    -- case suivante : x, y, largeur
    function form:Cell(h)
        local n = self.cols or 1
        local w = self.width / n
        local x, y = self.col * w, self.y
        if n <= 1 then
            self.y = self.y - h
            return x, y, w
        end
        self.rowH = math.max(self.rowH, h)
        self.col = self.col + 1
        if self.col >= n then
            self.y = self.y - self.rowH
            self.col, self.rowH = 0, 0
        end
        return x, y, w
    end
    function form:Gap(n)
        self:EndColumns()
        self.y = self.y - (n or 8)
    end
    function form:Header(text)
        self:EndColumns()
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, self.y)
        fs:SetText(text)
        self.y = self.y - 22
        return fs
    end
    function form:Check(text, get, set)
        local x, y = self:Cell(26)
        local c = ns.UI.Check(parent, text, function(v) set(v) changed() end)
        c:SetPoint("TOPLEFT", parent, "TOPLEFT", 4 + x, y - 2)
        table.insert(self.refreshers, function() c:SetChecked(get() and true or false) end)
        return c
    end
    -- reglage numerique : libelle, puis curseur et saisie - / +
    function form:Number(fmt, get, set, lo, hi, step)
        local x, y, w = self:Cell(44)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 8 + x, y)
        fs:SetText(labelOf(fmt))
        local sl = ns.UI.Slider(parent, math.min(w - 16, 260), lo, hi, step or 1, get, set, changed)
        sl:SetPoint("TOPLEFT", parent, "TOPLEFT", 8 + x, y - 16)
        table.insert(self.refreshers, function() sl:Refresh() end)
        return sl
    end
    -- choix dans une liste deroulante
    function form:Cycle(fmt, values, names, get, set)
        local x, y, w = self:Cell(44)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 8 + x, y)
        fs:SetText(labelOf(fmt))
        local function options()
            local list = {}
            for _, v in ipairs(values) do table.insert(list, { value = v, text = names[v] or tostring(v) }) end
            return list
        end
        local sel = ns.UI.Select(parent, math.min(w - 16, 200), options, get, set, changed)
        sel:SetPoint("TOPLEFT", parent, "TOPLEFT", 8 + x, y - 16)
        table.insert(self.refreshers, function() sel:Refresh() end)
        return sel
    end
    -- liste deroulante libre (options() dynamique), sur toute la largeur
    function form:Select(label, options, get, set, width)
        self:EndColumns()
        if label then
            local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, self.y)
            fs:SetText(label)
            self.y = self.y - 16
        end
        local sel = ns.UI.Select(parent, width or 200, options, get, set, changed)
        sel:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, self.y)
        self.y = self.y - 28
        table.insert(self.refreshers, function() sel:Refresh() end)
        return sel
    end
    -- ancien reglage a boutons (texte + - / +), garde pour les cas speciaux
    function form:Stepper(textFn, change)
        self:EndColumns()
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, self.y - 5)
        local function go(d)
            change(d * (IsShiftKeyDown() and 5 or 1))
            changed()
        end
        local minus = ns.UI.Button(parent, "-", 24, function() go(-1) end)
        minus:SetPoint("TOPLEFT", parent, "TOPLEFT", 230, self.y)
        local plus = ns.UI.Button(parent, "+", 24, function() go(1) end)
        plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
        self.y = self.y - 26
        table.insert(self.refreshers, function() fs:SetText(textFn()) end)
        return fs
    end
    return form
end

---------------------------------------------------------------------------
-- Barres de boutons (barres d action, barre de formes) : disposition
-- commune selon un reglage c = { buttons, perRow, size, spacing, backdrop,
-- padding, bgAlpha, alpha, mouseover }. Le cadre h porte h.back et
-- h.backBorder (ns.UI.Skin). pos : position enregistree (ou nil).
-- Barre dans la moitie basse de l ecran : son bord du bas reste fixe et les
-- lignes s ajoutent vers le haut (apres la premiere disposition seulement).
---------------------------------------------------------------------------

ns.ButtonBars = {}      -- { frame = , conf = fonction } : fondu au survol

function ns.LayoutButtonBar(h, buttons, n, c, pos)
    n = math.max(0, math.min(n, #buttons))
    local per = math.max(1, math.min(c.perRow, math.max(1, n)))
    local rows = math.max(1, math.ceil(n / per))
    local pad = c.backdrop and c.padding or 0
    local step = c.size + c.spacing
    local oldH = h:GetHeight()
    local top, bottom = h:GetTop(), h:GetBottom()
    local up = false
    if top and bottom then
        local mid = (top + bottom) / 2 * h:GetEffectiveScale()
        up = mid < UIParent:GetHeight() * UIParent:GetEffectiveScale() / 2
    end
    for j, b in ipairs(buttons) do
        b:ClearAllPoints()
        if j <= n then
            local col, row = (j - 1) % per, math.floor((j - 1) / per)
            b:SetSize(c.size, c.size)
            if up then
                b:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", pad + col * step, pad + row * step)
            else
                b:SetPoint("TOPLEFT", h, "TOPLEFT", pad + col * step, -(pad + row * step))
            end
        end
    end
    local cols = math.min(per, math.max(1, n))
    local newH = rows * c.size + (rows - 1) * c.spacing + 2 * pad
    h:SetSize(cols * c.size + (cols - 1) * c.spacing + 2 * pad, newH)
    if h.cuiLaidOut and up and pos and math.abs(newH - oldH) > 0.5 and type(pos.point) == "string"
        and not pos.point:find("BOTTOM") and type(pos.y) == "number" then
        pos.y = pos.y + (pos.point:find("TOP") and (newH - oldH) or (newH - oldH) / 2)
        ns.ApplyPos(h, pos)
    end
    h.cuiLaidOut = true
    -- fond : obsidienne a l opacite choisie, liseré du theme
    if h.back then
        local a = (c.bgAlpha or 75) / 100
        h.back:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], a)
        h.backBorder:SetColorTexture(C.border[1], C.border[2], C.border[3], math.min(1, a + 0.25))
        h.back:SetShown(c.backdrop)
        h.backBorder:SetShown(c.backdrop)
    end
    if not c.mouseover and not c.oocFade then h:SetAlpha(c.alpha) end
end

-- barres "estompees hors combat" : opacite gardee (part de l opacite choisie)
local OOC_ALPHA = 0.3

-- fondu des barres "visibles au survol" (et pendant qu on tient un sort) ;
-- "estompees hors combat" : pleines en combat ou au survol, sinon pales
local fader = CreateFrame("Frame")
fader:SetScript("OnUpdate", function(_, dt)
    local fighting
    for _, e in ipairs(ns.ButtonBars) do
        local h = e.frame
        local c = e.conf()
        if c and (c.mouseover or c.oocFade) and h:IsShown() then
            local active = h:IsMouseOver() or GetCursorInfo() or ns.moversShown or ns.quickBinding
            local want
            if c.mouseover then
                want = active and c.alpha or 0
            else
                if fighting == nil then fighting = InCombatLockdown() and true or false end
                want = (active or fighting) and c.alpha or c.alpha * OOC_ALPHA
            end
            local a = h:GetAlpha()
            if a ~= want then
                h:SetAlpha(want > a and math.min(want, a + dt * 5) or math.max(want, a - dt * 3))
            end
        end
    end
end)

-- Bouton qui recharge l interface. Sur ce client, ReloadUI appele par un
-- addon est bloque ("Echec d une action d interface...") : le bouton est
-- securise et execute la macro "/reload", comme si on la tapait.
-- before (facultatif) : appele juste avant ; renvoie false pour ne pas
-- recharger (etape d un assistant, confirmation...).
function ns.UI.ReloadButton(parent, text, width, before)
    local b = ns.UI.Button(parent, text, width, nil, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "/reload")
    b:SetScript("PreClick", function(self, _, down)
        -- un clic = appui + relachement : l action part sur l un des deux
        if (down and true or false) ~= GetCVarBool("ActionButtonUseKeyDown") then return end
        if InCombatLockdown() then return end
        if before and before() == false then self:SetAttribute("type", nil) end
    end)
    b:SetScript("PostClick", function(self)
        if not InCombatLockdown() then self:SetAttribute("type", "macro") end
    end)
    return b
end

-- Case a cocher plate : carre de 14 px, coche violette
-- Champ de saisie CorpUI (a la place d InputBoxTemplate) : fond sombre,
-- liseré du theme, or quand on ecrit ; Echap rend la main
function ns.UI.EditBox(parent, width, height)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width, height or 20)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetTextInsets(6, 6, 0, 0)
    ns.UI.Skin(e, 0.8)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:HookScript("OnEditFocusGained", function(self)
        self.cuiBorder:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    end)
    e:HookScript("OnEditFocusLost", function(self)
        self.cuiBorder:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    end)
    return e
end

-- Champ de recherche : loupe d or, texte d aide, croix pour effacer.
-- onChange(texte, parUtilisateur) ; Echap et la croix effacent.
function ns.UI.SearchBox(parent, width, onChange, hintText)
    local box = ns.UI.EditBox(parent, width, 20)
    box:SetTextInsets(20, 18, 0, 0)
    box:SetMaxLetters(40)
    local glass = box:CreateTexture(nil, "OVERLAY")
    glass:SetSize(12, 12)
    glass:SetPoint("LEFT", 5, 0)
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 20, 0)
    hint:SetPoint("RIGHT", -18, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    hint:SetText(hintText or L.SEARCH)
    local clear = CreateFrame("Button", nil, box)
    clear:SetSize(14, 14)
    clear:SetPoint("RIGHT", -3, 0)
    local x = clear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    x:SetPoint("CENTER")
    x:SetText("×")
    clear:Hide()
    local function sync()
        local empty = (box:GetText() or "") == ""
        hint:SetShown(empty and not box:HasFocus())
        clear:SetShown(not empty)
    end
    local function wipeText()
        box:SetText("")
        box:ClearFocus()
        if onChange then onChange("", true) end
    end
    clear:SetScript("OnClick", wipeText)
    box:SetScript("OnEscapePressed", wipeText)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self, user)
        sync()
        if onChange then onChange(self:GetText() or "", user) end
    end)
    box:HookScript("OnEditFocusGained", sync)
    box:HookScript("OnEditFocusLost", sync)
    return box
end

function ns.UI.Check(parent, text, onClick)
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetSize(24, 24)
    local box = CreateFrame("Frame", nil, c, "BackdropTemplate")
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 5, 0)
    box:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    box:SetBackdropColor(0, 0, 0, 0.6)
    borderColor(box, C.border)
    box:EnableMouse(false)
    local check = c:CreateTexture(nil, "OVERLAY")
    check:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
    check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
    -- coche : l accent eclairci, pour ressortir meme sur le theme sombre
    local function lit(v) return v + (1 - v) * 0.35 end
    ns.UI.Gradient(check, "VERTICAL", C.violet[1] * 0.75, C.violet[2] * 0.75, C.violet[3] * 0.75, 1, lit(C.violet[1]), lit(C.violet[2]), lit(C.violet[3]), 1)
    c:SetCheckedTexture(check)
    local label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", c, "RIGHT", 0, 0)
    label:SetText(text)
    label:SetTextColor(C.text[1], C.text[2], C.text[3])
    c.Text, c.label = label, label
    -- le texte est cliquable aussi
    c:SetHitRectInsets(0, -(label:GetStringWidth() + 4), 0, 0)
    c:HookScript("OnEnter", function() borderColor(box, C.gold) label:SetTextColor(1, 1, 1) end)
    c:HookScript("OnLeave", function() borderColor(box, C.border) label:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return c
end

-- Poignees de deplacement (grille, aimantation, reglage au pixel) :
-- voir Movers.lua (ns.UI.Mover, ns.SetMoversShown).

---------------------------------------------------------------------------
-- Valeurs d unite, compatibles avec les valeurs secretes de ce client.
-- La vie est secrete meme hors combat : une barre l accepte telle quelle,
-- un texte passe par AbbreviateNumbers / UnitHealthPercent.
---------------------------------------------------------------------------

-- Boutons d unite de CorpUI (cadres, groupe, raid) : le module Sorts au
-- clic leur pose ses attributs. Chaque module y inscrit ses boutons.
ns.unitButtons = {}
function ns.RegisterUnitButton(b)
    table.insert(ns.unitButtons, b)
    if ns.ApplyClickCast then ns.ApplyClickCast(b) end
end

ns.UF = {}

function ns.UF.Flag(fn, unit)
    if not fn then return false end
    local ok, v = pcall(fn, unit)
    if not ok or issecret(v) then return false end
    return v and true or false
end

function ns.UF.SetBar(bar, cur, max)
    local ok1 = pcall(bar.SetMinMaxValues, bar, 0, max)
    local ok2 = pcall(bar.SetValue, bar, cur)
    return ok1 and ok2
end

function ns.UF.Percent(unit, kind)
    local scale = CurveConstants and CurveConstants.ScaleTo100
    local fn = kind == "power" and UnitPowerPercent or UnitHealthPercent
    if not scale or not fn then return nil end
    local ok, p
    if kind == "power" then ok, p = pcall(fn, unit, nil, true, scale) else ok, p = pcall(fn, unit, true, scale) end
    return ok and p or nil
end

-- mode : "pct" (62%), "value" (1.3K / 2K), "both", "cur" (1.3K), "none"
function ns.UF.SetText(fs, unit, kind, cur, max, mode)
    if mode == "none" then fs:SetText("") return end
    if mode == "cur" then
        local okA, a = pcall(AbbreviateNumbers or tostring, cur)
        if okA and pcall(fs.SetFormattedText, fs, "%s", a) then return end
        if not pcall(fs.SetFormattedText, fs, "%d", cur) then fs:SetText("") end
        return
    end
    if mode == "pct" then
        local p = ns.UF.Percent(unit, kind)
        if p ~= nil and pcall(fs.SetFormattedText, fs, "%d%%", p) then return end
        fs:SetText("")
        return
    end
    local okA, a = pcall(AbbreviateNumbers or tostring, cur)
    local okB, b = pcall(AbbreviateNumbers or tostring, max)
    if okA and okB then
        local p = mode == "both" and ns.UF.Percent(unit, kind)
        if p ~= nil and pcall(fs.SetFormattedText, fs, "%s / %s  %d%%", a, b, p) then return end
        if pcall(fs.SetFormattedText, fs, "%s / %s", a, b) then return end
    end
    if not pcall(fs.SetFormattedText, fs, "%d / %d", cur, max) then fs:SetText("") end
end

function ns.UF.PowerColor(unit)
    local ok, _, token = pcall(UnitPowerType, unit)
    token = ok and not issecret(token) and token or "MANA"
    local c = PowerBarColor and PowerBarColor[token]
    if c and c.r then return c.r, c.g, c.b end
    if token == "RAGE" then return 0.78, 0.15, 0.15 end
    if token == "ENERGY" then return 1, 0.85, 0.1 end
    return 0, 0.44, 0.87
end

function ns.UF.HealthColor(unit)
    if ns.UF.Flag(UnitIsPlayer, unit) then
        local _, class = UnitClass(unit)
        if class and not issecret(class) and ns.ClassColor then return ns.ClassColor(class) end
    end
    if ns.UF.Flag(UnitIsTapDenied, unit) then return 0.5, 0.5, 0.5 end
    local ok, r = pcall(UnitReaction, unit, "player")
    if ok and r and not issecret(r) then
        if r <= 3 then return 0.8, 0.15, 0.15 end
        if r == 4 then return 0.9, 0.8, 0.1 end
    end
    return 0.2, 0.75, 0.25
end

-- Estompe une unite hors de portee ; SetAlphaFromBoolean accepte un
-- booleen secret, sinon on lit la valeur si elle est lisible
function ns.UF.Range(frame, unit, faded)
    faded = faded or 0.45
    if UnitIsUnit(unit, "player") then frame:SetAlpha(1) return end
    local ok, inRange, checked = pcall(UnitInRange, unit)
    if not ok then return end
    if frame.SetAlphaFromBoolean and pcall(frame.SetAlphaFromBoolean, frame, inRange, 1, faded) then return end
    if not issecret(inRange) and not issecret(checked) then
        frame:SetAlpha((checked and not inRange) and faded or 1)
    end
end

-- Auras d une unite, meme en combat ou leurs donnees sont secretes :
-- comme les plaques de Blizzard, on part des identifiants (jamais secrets),
-- et "posee par moi" est demande au client (IsAuraFilteredOutByInstanceID).
-- Chaque entree : { id, aura (champs peut-etre secrets), mine (true/false/nil) }
-- wantMine : demander "a moi" meme sans tri (sinon seulement si mineOnly).
-- 2e retour : false si le client a refuse le filtre.
function ns.UnitAuraList(unit, filter, mineOnly, max, wantMine)
    local out = {}
    local accepted = true
    max = max or 40
    local CU = C_UnitAuras
    if not CU then return out end
    local function isMine(id)
        if not CU.IsAuraFilteredOutByInstanceID then return nil end
        local ok, filtered = pcall(CU.IsAuraFilteredOutByInstanceID, unit, id, filter .. "|PLAYER")
        if ok and not issecret(filtered) and type(filtered) == "boolean" then return not filtered end
        return nil
    end
    if CU.GetUnitAuraInstanceIDs and CU.GetAuraDataByAuraInstanceID then
        local ok, ids = pcall(CU.GetUnitAuraInstanceIDs, unit, filter)
        if ok and type(ids) == "table" then
            -- donnees : par identifiant, sinon la liste du client a la meme
            -- place (GetUnitAuras, celle des plaques de Blizzard)
            local all
            local function byPos(i)
                if all == nil then
                    local okL, l = pcall(CU.GetUnitAuras, unit, filter)
                    all = (okL and type(l) == "table") and l or false
                end
                if not all then return nil end
                local okI, v = pcall(function() return all[i] end)
                return okI and v or nil
            end
            for i, id in ipairs(ids) do
                if #out >= max then break end
                local mine
                if mineOnly or wantMine then mine = isMine(id) end
                -- "a moi" inconnu : montree (mieux que rien)
                if not mineOnly or mine ~= false then
                    local okA, a = pcall(CU.GetAuraDataByAuraInstanceID, unit, id)
                    if not (okA and (issecret(a) or type(a) == "table")) then a = CU.GetUnitAuras and byPos(i) or nil end
                    -- rien de lisible : l icone restera vide, la duree passe par l id
                    if not issecret(a) and type(a) ~= "table" then a = {} end
                    table.insert(out, { id = id, aura = a, mine = mine })
                end
            end
            return out, true
        end
        if not ok then accepted = false end
    end
    -- ancien chemin : par index ; filtre "a moi" refuse : tri par la source
    -- quand elle est lisible (sinon montree)
    local f = mineOnly and (filter .. "|PLAYER") or filter
    local sortMine = false
    if mineOnly and not pcall(CU.GetAuraDataByIndex, unit, 1, f) then f, sortMine = filter, true end
    if not pcall(CU.GetAuraDataByIndex, unit, 1, f) then return out, false end
    for i = 1, 40 do
        if #out >= max then break end
        local ok, a = pcall(CU.GetAuraDataByIndex, unit, i, f)
        if not ok or type(a) ~= "table" then break end
        local okI, id = pcall(function() return a.auraInstanceID end)
        id = okI and id or nil
        local mine = mineOnly and not sortMine or nil
        if id then
            local m = isMine(id)
            if m ~= nil then mine = m end
        end
        if mine == nil then
            local okM, v = pcall(function() return a.isFromPlayerOrPlayerPet end)
            if okM and not issecret(v) and type(v) == "boolean" then mine = v end
        end
        if not sortMine or mine ~= false then table.insert(out, { id = id, aura = a, mine = mine }) end
    end
    return out, accepted or #out > 0
end

---------------------------------------------------------------------------
-- Auras affichees par le client lui-meme (conteneur "AuraContainer" de
-- Blizzard, cree par l addon) : en combat, ce client refuse TOUTE lecture
-- d auras a un addon ("Auras cannot be accessed when secret while tainted"),
-- mais ce conteneur securise les lit et les range seul. CorpUI ne fournit
-- que l habillage de chaque bouton (icone, liseré colore par type,
-- balayage, charges, temps) et la disposition.
--
-- spec = {
--   width, height, spacing, perRow, max,
--   noMouse, cancel = "RightButtonUp" (clic qui annule), tooltipAnchor,
--   grow = "up" | "down", fromRight = bool,
--   time = "none" | "below" | "native", countSize,
--   anchor = { relativeTo, relativePoint, x, y } (point = coin de depart),
--   groups = { { key, filter, candidate, desaturate, enabled }, ... },
-- }
-- Renvoie un objet { frame, Apply(spec), SetUnit(unit), Refresh() } ou nil
-- si le client n a pas ce conteneur.
---------------------------------------------------------------------------
local TIME_TEXT_H = 10
local DISPEL_RGB = {
    Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 },
    Poison = { 0, 0.6, 0 }, None = { 0.8, 0, 0 },
}

function ns.NativeAuras(parent, unit, spec)
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or type(c) ~= "table" or not c.AddAuraGroup then return nil end
    local na = { frame = c, buttons = {}, spec = spec }

    local colorMap
    if CreateColor then
        colorMap = {}
        for k, v in pairs(DISPEL_RGB) do colorMap[k] = CreateColor(v[1], v[2], v[3]) end
    end

    -- habillage d un bouton, a sa creation par le conteneur
    local function init(btn, g)
        local e = { btn = btn, g = g }
        -- sans souris : les clics passent au cadre dessous (cadres de groupe)
        if spec.noMouse then
            pcall(btn.EnableMouse, btn, false)
            pcall(btn.SetMouseClickEnabled, btn, false)
        end
        -- clic qui annule l aura (fait par le bouton du client, meme en combat)
        if spec.cancel then pcall(btn.SetCancelAuraButtons, btn, spec.cancel) end
        if spec.tooltipAnchor then pcall(btn.SetTooltipAnchorPoint, btn, spec.tooltipAnchor) end
        local edge = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
        edge:SetPoint("TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", 1, -1)
        local bc = ns.COLORS.border
        edge:SetColorTexture(bc[1], bc[2], bc[3], 1)
        -- liseré du type de debuff : blanc teinte par le client
        local typed = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
        typed:SetAllPoints(edge)
        typed:SetColorTexture(1, 1, 1, 1)
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        e.icon = icon
        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetReverse(true)
        e.cd = cd
        local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT", 2, -2)
        e.count = count
        local time = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        time:SetPoint("TOP", btn, "BOTTOM", 0, -1)
        e.time = time
        pcall(btn.SetIcon, btn, icon)
        pcall(btn.SetDurationCooldown, btn, cd)
        pcall(btn.SetApplicationCount, btn, count)
        if Enum and Enum.CustomAuraButtonDispelTypeTextureStyle then
            pcall(btn.AddDispelTypeTexture, btn, typed, {
                style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
                showWhenHarmful = true, showWithoutDispelType = true,
                customDispelColorMap = colorMap,
            })
        else
            typed:Hide()
        end
        table.insert(na.buttons, e)
        na:Style(e)
    end

    -- un bouton selon le reglage courant
    function na:Style(e)
        local s = self.spec
        e.btn:SetSize(s.width, s.height)
        local h = s.height
        if s.height < s.width then
            local r = (1 - s.height / s.width) / 2 * 0.84
            e.icon:SetTexCoord(0.08, 0.92, 0.08 + r, 0.92 - r)
        else
            e.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        e.icon:SetDesaturated(e.g.desaturate and true or false)
        pcall(e.cd.SetHideCountdownNumbers, e.cd, s.time ~= "native")
        local font = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
        local okF, fs = pcall(e.cd.GetCountdownFontString, e.cd)
        if okF and type(fs) == "table" then pcall(fs.SetFont, fs, font, math.max(7, math.floor(h * 0.45)), "OUTLINE") end
        pcall(e.count.SetFont, e.count, font, s.countSize or math.max(7, math.floor(h * 0.5)), "OUTLINE")
        if s.time == "below" then
            if not e.timeOn then e.timeOn = pcall(e.btn.SetDurationText, e.btn, e.time) end
            e.time:Show()
        else
            if e.timeOn then pcall(e.btn.ClearDurationText, e.btn) e.timeOn = false end
            e.time:Hide()
        end
    end

    pcall(c.SetUnit, c, unit)
    for i, g in ipairs(spec.groups) do
        local okG, err = pcall(c.AddAuraGroup, c, g.key, g.filter, {
            maxFrameCount = spec.max,
            initializeFrame = function(btn) init(btn, g) end,
            candidateFilters = g.candidate,
            layout = { layoutIndex = i },
        })
        if not okG then geterrorhandler()(err) end
    end

    function na:Apply(newSpec)
        local s = newSpec or self.spec
        self.spec = s
        local fr = self.frame
        local timeH = s.time == "below" and TIME_TEXT_H or 0
        local A = AnchorUtil and AnchorUtil.FlowDirection
        local up = s.grow == "up"
        local point = (up and "BOTTOM" or "TOP") .. (s.fromRight and "RIGHT" or "LEFT")
        pcall(fr.SetFlowLayoutAnchorPoint, fr, point)
        if A then
            pcall(fr.SetFlowLayoutGrowthDirection, fr, s.fromRight and A.Left or A.Right, up and A.Up or A.Down)
        end
        pcall(fr.SetFlowLayoutMaximumLineSize, fr, s.perRow * (s.width + s.spacing))
        fr:ClearAllPoints()
        if s.anchor then
            local p = s.anchor
            fr:SetPoint(point, p[1] or fr:GetParent(), p[2] or point, p[3] or 0, p[4] or 0)
        else
            fr:SetPoint(point, fr:GetParent(), point, 0, 0)
        end
        for i, g in ipairs(s.groups) do
            pcall(fr.SetAuraGroupEnabled, fr, g.key, g.enabled ~= false)
            pcall(fr.SetAuraGroupMaxFrameCount, fr, g.key, s.max)
            pcall(fr.SetAuraGroupCandidateFilters, fr, g.key, g.candidate)
            pcall(fr.SetAuraGroupLayout, fr, g.key, {
                elementWidth = s.width, elementHeight = s.height + timeH,
                elementSpacing = s.spacing, lineSpacing = s.spacing, groupSpacing = s.spacing,
                groupLineSpacing = s.spacing, layoutIndex = i,
            })
        end
        -- les groupes ont pu changer de reglage (desaturation)
        for _, e in ipairs(self.buttons) do
            for _, g in ipairs(s.groups) do if g.key == e.g.key then e.g = g end end
            self:Style(e)
        end
        self:Refresh()
    end

    function na:SetUnit(u) pcall(self.frame.SetUnit, self.frame, u) end
    function na:Refresh() pcall(self.frame.UpdateAllAuras, self.frame) end

    na:Apply(spec)
    return na
end

-- Un seul emplacement d aura (le premier debuff d un filtre), affiche par
-- le client : build(btn) habille le bouton et y inscrit ses textures de
-- type (btn:AddDispelTypeTexture). Le bouton fait 1 px, sans souris : ses
-- textures peuvent s accrocher ailleurs (tout le tour d un cadre).
-- Renvoie { frame, slot, SetUnit(u), SetFilter(f), SetEnabled(v) } ou nil.
function ns.NativeAuraSlot(parent, unit, filter, build)
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or type(c) ~= "table" or not c.AddAuraSlot then return nil end
    pcall(c.SetUnit, c, unit)
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT")
    local okS, err = pcall(c.AddAuraSlot, c, "slot", filter, {
        initializeFrame = function(btn)
            pcall(btn.EnableMouse, btn, false)
            pcall(btn.SetMouseClickEnabled, btn, false)
            btn:SetSize(1, 1)
            build(btn)
        end,
    })
    if not okS then geterrorhandler()(err) return nil end
    local okF, slot = pcall(c.GetAuraSlotFrame, c, "slot")
    if okF and type(slot) == "table" then
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", parent, "TOPLEFT")
    end
    local o = { frame = c, slot = okF and slot or nil }
    function o:SetUnit(u) pcall(c.SetUnit, c, u) end
    function o:SetFilter(f) pcall(c.SetAuraSlotFilterString, c, "slot", f) end
    function o:SetEnabled(v) pcall(c.SetAuraSlotEnabled, c, "slot", v and true or false) end
    return o
end

-- couleurs par type de debuff, pour les textures inscrites a la main
function ns.DispelColorMap()
    if not CreateColor then return nil end
    local m = {}
    for k, v in pairs(DISPEL_RGB) do m[k] = CreateColor(v[1], v[2], v[3]) end
    return m
end

-- Sonde : ce que le client rend pour les auras d une unite (diagnostic,
-- enregistre dans CorpUIDB.auraProbe et lisible apres /reload)
function ns.AuraProbe(unit, filter)
    local CU = C_UnitAuras or {}
    local L2 = {}
    local function d(v)
        if issecret(v) then return "SECRET" end
        if type(v) == "table" then return "table" end
        return tostring(v)
    end
    local function add(s) table.insert(L2, s) end
    add("combat=" .. tostring(InCombatLockdown()) .. " unit=" .. unit .. " filter=" .. filter)
    local ok, ids = pcall(CU.GetUnitAuraInstanceIDs, unit, filter)
    local nIds = (ok and type(ids) == "table") and #ids or -1
    add("GetUnitAuraInstanceIDs ok=" .. tostring(ok) .. " r=" .. (ok and d(ids) or tostring(ids)) .. " n=" .. nIds)
    local id = nIds > 0 and ids[1] or nil
    if id then
        add("id1=" .. d(id))
        local okA, a = pcall(CU.GetAuraDataByAuraInstanceID, unit, id)
        add("ByInstanceID ok=" .. tostring(okA) .. " r=" .. (okA and d(a) or tostring(a)))
        if okA and (issecret(a) or type(a) == "table") then
            for _, k in ipairs({ "icon", "name", "spellId", "duration", "expirationTime", "isFromPlayerOrPlayerPet", "auraInstanceID" }) do
                local okF, v = pcall(function() return a[k] end)
                add("  ." .. k .. " ok=" .. tostring(okF) .. " " .. (okF and d(v) or tostring(v)))
            end
        end
        local okF, out = pcall(CU.IsAuraFilteredOutByInstanceID, unit, id, filter .. "|PLAYER")
        add("IsAuraFilteredOut ok=" .. tostring(okF) .. " r=" .. (okF and d(out) or tostring(out)))
        local okD, du = pcall(CU.GetAuraDuration, unit, id)
        add("GetAuraDuration ok=" .. tostring(okD) .. " r=" .. (okD and d(du) or tostring(du)))
    end
    local okL, l = pcall(CU.GetUnitAuras, unit, filter)
    add("GetUnitAuras ok=" .. tostring(okL) .. " r=" .. (okL and d(l) or tostring(l)) .. " n=" .. ((okL and type(l) == "table") and #l or -1))
    local okP, first = false, nil
    if okL and type(l) == "table" then okP, first = pcall(function() return l[1] end) end
    if okP and (issecret(first) or first) then
        local a = first
        add("  [1]=" .. d(a))
        for _, k in ipairs({ "icon", "auraInstanceID", "name" }) do
            local okF, v = pcall(function() return a[k] end)
            add("  [1]." .. k .. " ok=" .. tostring(okF) .. " " .. (okF and d(v) or tostring(v)))
        end
    end
    local okI, b = pcall(CU.GetAuraDataByIndex, unit, 1, filter)
    add("ByIndex ok=" .. tostring(okI) .. " r=" .. (okI and d(b) or tostring(b)))
    local list = ns.UnitAuraList(unit, filter, false, 40)
    add("UnitAuraList n=" .. #list)
    return L2
end

-- nombre de charges a afficher ("" sous 2), meme secret
function ns.AuraCountText(unit, id, aura)
    local CU = C_UnitAuras
    if id and CU and CU.GetAuraApplicationDisplayCount then
        local ok, s = pcall(CU.GetAuraApplicationDisplayCount, unit, id, 2)
        if ok and (issecret(s) or type(s) == "string") then return s end
    end
    local ok, s = pcall(function()
        local n = aura.applications
        if n and n > 1 then return tostring(n) end
        return ""
    end)
    return ok and s or ""
end

-- Infobulle de l unite au survol d un cadre (comme les cadres du jeu) ;
-- reglage dans Infobulles (ns.TipsOnFrames)
function ns.UF.HoverTooltip(b)
    b:HookScript("OnEnter", function(self)
        if ns.TipsOnFrames and not ns.TipsOnFrames() then return end
        local unit = self:GetAttribute("unit")
        if not unit or not UnitExists(unit) then return end
        if GameTooltip_SetDefaultAnchor then
            pcall(GameTooltip_SetDefaultAnchor, GameTooltip, self)
        else
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        end
        if pcall(GameTooltip.SetUnit, GameTooltip, unit) then GameTooltip:Show() end
        self.cuiTip = true
    end)
    b:HookScript("OnLeave", function(self)
        if self.cuiTip then
            self.cuiTip = nil
            GameTooltip:Hide()
        end
    end)
end

-- Soins entrants sur une unite. Le calculateur du client
-- (CreateUnitHealPredictionCalculator) borne le soin a la vie manquante ;
-- sinon UnitGetIncomingHeals. Valeur souvent secrete : elle va telle quelle
-- dans une barre (permis).
local healCalc
function ns.UF.IncomingHeals(unit)
    if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
        if healCalc == nil then
            local ok, cl = pcall(CreateUnitHealPredictionCalculator)
            healCalc = ok and cl or false
            if healCalc and Enum and Enum.UnitIncomingHealClampMode then
                pcall(healCalc.SetIncomingHealClampMode, healCalc, Enum.UnitIncomingHealClampMode.MissingHealth)
            end
        end
        if healCalc and pcall(UnitGetDetailedHealPrediction, unit, "player", healCalc) then
            local ok, v = pcall(healCalc.GetIncomingHeals, healCalc)
            if ok then return v end
        end
    end
    if UnitGetIncomingHeals then
        local ok, v = pcall(UnitGetIncomingHeals, unit)
        if ok then return v end
    end
    return nil
end

-- Barre de soins entrants accrochee au bout du remplissage d une barre de
-- vie (coupee a ses bords), de la meme largeur qu elle. nil si la barre de
-- vie n a pas de texture de remplissage.
function ns.UF.HealBar(hp)
    local fill = hp.GetStatusBarTexture and hp:GetStatusBarTexture()
    if not fill then return nil end
    local clip = CreateFrame("Frame", nil, hp)
    clip:SetAllPoints(hp)
    clip:SetFrameLevel(hp:GetFrameLevel() + 1)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    local bar = CreateFrame("StatusBar", nil, clip)
    bar:SetStatusBarTexture(ns.BAR_TEXTURE)
    bar:SetStatusBarColor(0.1, 0.9, 0.4, 0.55)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    bar:SetWidth(math.max(1, hp:GetWidth() or 1))
    hp:HookScript("OnSizeChanged", function(_, w) if w and w > 0 then bar:SetWidth(w) end end)
    bar:Hide()
    return bar
end

-- soins entrants sur la barre ; on = reglage actif
function ns.UF.UpdateHeal(bar, unit, on)
    if not bar then return end
    if not on then bar:Hide() return end
    local v = ns.UF.IncomingHeals(unit)
    local okM, max = pcall(UnitHealthMax, unit)
    if okM and (issecret(v) or type(v) == "number") and ns.UF.SetBar(bar, v, max) then
        bar:Show()
    else
        bar:Hide()
    end
end

function ns.UF.Bar(parent, h)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(h)
    bar:SetStatusBarTexture(ns.BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    return bar
end

-- Cache un cadre de Blizzard sans toucher a son code : on le range dans un
-- parent cache (methode d ElvUI). Contrairement a la transparence, ses
-- boutons enfants deviennent aussi invisibles ET impossibles a cliquer.
-- Hors combat seulement (les cadres proteges refusent SetParent en combat).
-- names : noms globaux, ou chemins comme "MinimapCluster.BorderTop".
ns.hiddenParent = CreateFrame("Frame", "CorpUIHiddenParent", UIParent)
ns.hiddenParent:Hide()
local hiddenOrig = {}

local function resolve(path)
    local f = _G
    for part in path:gmatch("[^%.]+") do
        if type(f) ~= "table" then return nil end
        f = f[part]
    end
    return f
end

function ns.HideBlizzard(names, hide)
    if InCombatLockdown() then return false end
    for _, name in ipairs(names) do
        local f = resolve(name)
        if type(f) == "table" and f.SetParent then
            if hide then
                if not hiddenOrig[f] then hiddenOrig[f] = f:GetParent() or UIParent end
                pcall(f.SetParent, f, ns.hiddenParent)
            elseif hiddenOrig[f] then
                pcall(f.SetParent, f, hiddenOrig[f])
                hiddenOrig[f] = nil
            end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Notifications internes : les interfaces s abonnent ici
---------------------------------------------------------------------------

ns.inits = {}      -- lances a PLAYER_LOGIN (creation des cadres)
local listeners = {}
function ns.Listen(fn) table.insert(listeners, fn) end

local changePending = false
function ns.Changed()
    if changePending then return end
    changePending = true
    C_Timer.After(0, function()
        changePending = false
        for _, fn in ipairs(listeners) do
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
    end)
end

---------------------------------------------------------------------------
-- Apercu des cadres pendant leur reglage : tant qu un panneau inscrit
-- (ns.PreviewPanel : Cadres, Groupe) est ouvert, les cadres sans unite
-- s affichent avec des donnees fictives (Cadres, Groupe, Auras) : cadres
-- d unite, groupe et raid, sans case a cocher. Les cadres etant securises,
-- chaque module n applique l apercu qu hors combat.
---------------------------------------------------------------------------

ns.previewOpen = false
local previewPanels = {}

-- partie ("units", "party", "raid") en apercu en ce moment : toutes, tant
-- que la page est ouverte
function ns.PreviewOn(part)
    return ns.previewOpen and true or false
end

local function syncPreview()
    local open = false
    for p in pairs(previewPanels) do
        if p:IsVisible() then open = true end
    end
    if open ~= ns.previewOpen then
        ns.previewOpen = open
        ns.Changed()
    end
end

function ns.PreviewPanel(panel)
    if previewPanels[panel] then return end
    previewPanels[panel] = true
    -- choix des parties de la premiere version (cases a cocher retirees)
    local root = ns.InitRoot()
    root.preview = nil
    panel:HookScript("OnShow", syncPreview)
    -- plusieurs panneaux se cachent ensemble : on regarde a l image suivante
    panel:HookScript("OnHide", function() C_Timer.After(0, syncPreview) end)
    syncPreview()
end

---------------------------------------------------------------------------
-- Sauvegarde globale
---------------------------------------------------------------------------

-- reglages du socle toujours presents (aussi apres un changement de profil)
function ns.RootDefaults(db)
    if type(db.minimap) ~= "table" then db.minimap = {} end
    if db.minimap.angle == nil then db.minimap.angle = 200 end
    if db.minimap.hide == nil then db.minimap.hide = false end
end

-- Idempotent : chaque module peut l appeler avant de lire sa sous-table
function ns.InitRoot()
    if ns.root then return ns.root end
    if type(CorpUIDB) ~= "table" then CorpUIDB = {} end
    local db = CorpUIDB
    -- reprise de BuffForever : langue et minicarte etaient dans les buffs
    local b = db.buffs
    if type(b) == "table" then
        if db.lang == nil and b.lang then db.lang = b.lang end
        if db.minimap == nil and type(b.minimap) == "table" then db.minimap = b.minimap end
        b.lang, b.minimap = nil, nil
    end
    ns.root = db
    -- profil du personnage (Profils.lua) : avant toute lecture des reglages
    if ns.ProfileSwitch then ns.ProfileSwitch(db) end
    ns.RootDefaults(db)
    applyTheme(db.theme)
    return db
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------

ns.modules = {}

function ns.RegisterModule(m)
    table.insert(ns.modules, m)
end

-- commande ou alias affiche par /corp (skins, tooltips, ah...)
local function findModule(command)
    for _, m in ipairs(ns.modules) do
        if m.command == command then return m end
    end
    for _, m in ipairs(ns.modules) do
        if m.alias == command then return m end
    end
end

---------------------------------------------------------------------------
-- Langue
---------------------------------------------------------------------------

function ns.LangCommand(code)
    code = code and strtrim(strlower(code)) or ""
    if code == "" then
        ns.Say(L.LANG_LIST)
        local active = ns.ActiveLocale()
        for _, lang in ipairs(ns.LANGUAGES) do
            local mark = lang.code == active and " |cff00ff00<|r" or ""
            ns.Chat(string.format("  |cffffff00/corp lang %s|r - %s%s", lang.short, lang.name, mark))
        end
        ns.Chat("  |cffffff00/corp lang auto|r")
        return
    end
    if code == "auto" then
        ns.root.lang = nil
    else
        local found
        for _, lang in ipairs(ns.LANGUAGES) do
            if lang.short == code or strlower(lang.code) == code then found = lang.code break end
        end
        if not found and code == "zh" then found = "zhCN" end
        if not found then
            ns.Say(string.format(L.LANG_UNKNOWN, code))
            return
        end
        ns.root.lang = found
    end
    local name = ns.ActiveLocale()
    for _, lang in ipairs(ns.LANGUAGES) do
        if lang.code == name then name = lang.name break end
    end
    ns.Say(string.format(L.LANG_SET, name))
end

function ns.ToggleMinimap()
    ns.root.minimap.hide = not ns.root.minimap.hide
    ns.Changed()
end

---------------------------------------------------------------------------
-- Commande /corp
---------------------------------------------------------------------------

local function help()
    ns.Say(L.HELP_TITLE)
    for _, m in ipairs(ns.modules) do
        local alias = m.alias and (" (" .. m.alias .. ")") or ""
        ns.Chat(string.format("  |cffffff00/corp %s|r%s - %s", m.command, alias, m.desc()))
    end
    ns.Chat(string.format("  |cffffff00/corp lang|r - %s", L.HELP[16]))
    ns.Chat(string.format("  |cffffff00/corp minimap|r - %s", L.HELP[11]))
end

SLASH_CORPUI1 = "/corp"
SLASH_CORPUI2 = "/corpui"
SLASH_CORPUI3 = "/cui"
SLASH_CORPUI4 = "/ht"            -- ancien nom (HystéTools), par habitude
SlashCmdList["CORPUI"] = function(input)
    ns.InitRoot()
    local cmd, rest = strsplit(" ", strtrim(input or ""), 2)
    cmd = strlower(cmd or "")
    local m = findModule(cmd)
    if cmd == "" then
        ns.ToggleMain()
    elseif m then
        m.Slash(rest or "")
    elseif cmd == "lang" or cmd == "langue" or cmd == "language" then
        ns.LangCommand(rest)
    elseif cmd == "minimap" then
        ns.ToggleMinimap()
    else
        help()
    end
end

---------------------------------------------------------------------------
-- Fenetre principale : une colonne d onglets (General + un par module) et,
-- a droite, le panneau du module choisi. Les modules n ont plus de fenetre
-- a eux : ils construisent un panneau (ns.NewPanel) et l affichent avec
-- ns.ShowPanel. Pas d ajout dans UISpecialFrames (taint) : on ferme avec
-- la croix, /corp ou la minicarte.
---------------------------------------------------------------------------

local TAB_W, TAB_H, PAD, HEAD_H = 180, 26, 12, 50
-- taille fixe par defaut (ne bouge plus d une page a l autre) ; elle ne
-- grandit que pour un panneau seul plus grand (Persos, Sorts...)
local MIN_W, MIN_H = 480, 560
local CAT_H = 22
local SECTION_GAP = 14

-- Pages de la fenetre. Une page empile, en sections, les reglages de
-- plusieurs modules (leurs commandes) ; "@general" = les reglages communs.
-- Les entrees { cat = ... } sont de simples intertitres de la colonne.
-- Un module absent de la liste a sa propre page, en fin de colonne.
local PAGES = {
    { key = "general", label = "TAB_GENERAL", icon = ns.LOGO, cmds = { "@general", "profils" } },
    { cat = "CAT_INTERFACE" },
    -- un seul panneau, l editeur de tous les cadres (liste deroulante), qui defile
    { key = "units", label = "PAGE_UNITS", cmds = { "cadres" }, scroll = true },
    { key = "bars", label = "PAGE_BARS", cmds = { "barres", "xp" } },
    { key = "map", label = "PAGE_MAP", cmds = { "minicarte", "infos", "quetes" } },
    { key = "plates", label = "PAGE_PLATES", cmds = { "plaques", "infobulles" } },
    { key = "chat", label = "PAGE_CHAT", cmds = { "chat", "compteur" } },
    { key = "bags", label = "PAGE_BAGS", cmds = { "sacs", "butin", "marchand" } },
    { key = "skins", cmds = { "habillage" } },
    -- groupe et raid (06/10) : intendance (buffs, dissipation, rappels), outils de raid
    { cat = "CAT_RAID" },
    { key = "buffs", label = "PAGE_RAIDCARE", cmds = { "buffs", "dissipation", "rappels" } },
    { key = "cd", cmds = { "cd" } },
    { key = "notes", cmds = { "note" } },
    { key = "raid", cmds = { "raid" } },
    { key = "inv", cmds = { "inv" } },
    { key = "clics", cmds = { "clics" } },
    { cat = "CAT_TOOLS" },
    { key = "persos", cmds = { "persos" } },
    { key = "metiers", cmds = { "metiers", "dez" } },
    -- hotel des ventes : reglages (prix, vente, volet) et comptabilite
    { key = "hv", cmds = { "hv", "compta" } },
    { key = "talents", cmds = { "talents" } },
    { key = "sorts", cmds = { "sorts" } },
    { key = "jeux", label = "PAGE_GAMES", cmds = { "murloc", "minerais" } },
}
local MEDIA = ns.MEDIA
local C = ns.COLORS

local main, content, tabCol
local scroll, sheet, track, thumb   -- defilement des pages a plusieurs sections
local tabs = {}       -- onglets (un par page), dans l ordre
local headers = {}    -- intertitres de la colonne
local descs = {}      -- nom du panneau -> fonction de description du module
local pageOf = {}     -- nom du panneau -> page
local tabsNeed        -- hauteur de la colonne d onglets
local panels = {}     -- nom -> panneau
local current         -- panneau affiche seul (page d un seul module)
local currentPage
local building        -- construction des sections : ShowPanel ne fait rien
local stacking
local fitMain, stack
local searchBox, results   -- recherche dans les options (plus bas)

-- Une image etiree garde ses proportions : on recadre par SetTexCoord
-- (iw, ih = proportions de l image source)
local function cover(tex, w, h, iw, ih)
    if not w or w <= 0 or not h or h <= 0 then return end
    local fw, fh = 1, 1
    if w / h > iw / ih then fh = (iw / ih) / (w / h) else fw = (w / h) / (iw / ih) end
    tex:SetTexCoord(0.5 - fw / 2, 0.5 + fw / 2, 0.5 - fh / 2, 0.5 + fh / 2)
end

local function buildMain()
    ns.root.main = ns.root.main or { point = "CENTER", x = 0, y = 40 }
    local store = ns.root.main
    main = CreateFrame("Frame", "CorpUIMain", UIParent, "BackdropTemplate")
    main:SetSize(TAB_W + MIN_W + PAD * 3, MIN_H)
    ns.ApplyPos(main, store)
    main:SetFrameStrata("DIALOG")
    main:SetToplevel(true)
    main:SetClampedToScreen(true)
    main:SetMovable(true)
    main:EnableMouse(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.PinTop(self, store, true)
    end)
    main:SetScript("OnShow", function(self) ns.PinTop(self, store) end)
    ns.UI.SetBackdrop(main, 0.97)
    ns.UI.Shadow(main, 5)
    main:Hide()

    -- fond : cercle runique, recadre sans deformation
    local bg = main:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetTexture(MEDIA .. "theme_bg")
    ns.TintThemeTexture(bg, 1)
    bg:SetAlpha(0.85)

    -- bandeau : cristal et trainees violettes, filigrane d or en dessous
    local head = main:CreateTexture(nil, "BACKGROUND", nil, 2)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(HEAD_H - 6)
    head:SetTexture(MEDIA .. "theme_header")
    ns.TintThemeTexture(head, 1)
    local headShade = main:CreateTexture(nil, "BACKGROUND", nil, 3)
    headShade:SetAllPoints(head)
    ns.UI.Gradient(headShade, "VERTICAL", 0, 0, 0, 0.55, 0, 0, 0, 0)
    local fili = main:CreateTexture(nil, "ARTWORK")
    fili:SetPoint("TOPLEFT", main, "TOPLEFT", 6, -(HEAD_H - 14))
    fili:SetPoint("TOPRIGHT", main, "TOPRIGHT", -6, -(HEAD_H - 14))
    fili:SetHeight(14)
    fili:SetTexture(MEDIA .. "theme_filigree")
    if ns.MODERN then fili:Hide() end

    main:SetScript("OnSizeChanged", function(self, w, h)
        cover(bg, w, h, 1, 1)
        -- bandeau : on garde la gauche (le cristal), recadre en hauteur
        local hh = HEAD_H - 6
        local fh = math.min(1, (hh / w) * 4)
        head:SetTexCoord(0, 1, 0.5 - fh / 2, 0.5 + fh / 2)
    end)

    local logo = main:CreateTexture(nil, "ARTWORK", nil, 2)
    logo:SetSize(38, 38)
    logo:SetPoint("TOPLEFT", 8, -3)
    logo:SetTexture(MEDIA .. "logo128")
    local title = main:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 20)
    title:SetPoint("LEFT", logo, "RIGHT", 6, 1)
    title:SetText(ns.TITLE)
    local ver = main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ver:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 2)
    ver:SetText("v" .. ns.VERSION)

    -- fermeture : croix plate, rouge au survol
    local close = CreateFrame("Button", nil, main)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -8, -10)
    local x = close:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(x, 16)
    x:SetPoint("CENTER", 0, 1)
    x:SetText("×")
    x:SetTextColor(C.text[1], C.text[2], C.text[3])
    close:SetScript("OnEnter", function() x:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function() x:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    close:SetScript("OnClick", function() main:Hide() end)

    -- verrouiller / deverrouiller l interface, a cote de la croix
    local lock = ns.UI.Button(main, "", 110, function() ns.SetMoversShown(not ns.moversShown) end)
    lock:SetSize(110, 20)
    lock:SetPoint("RIGHT", close, "LEFT", -6, 0)
    local function syncLock()
        lock:SetText(ns.moversShown and L.MOVER_LOCK or L.MAIN_UNLOCK)
        local c = ns.moversShown and C.gold or C.text
        lock.cuiText:SetTextColor(c[1], c[2], c[3])
    end
    syncLock()
    ns.Listen(syncLock)

    -- colonne des onglets : un ton plus sombre, filet violet a droite
    tabCol = CreateFrame("Frame", nil, main)
    tabCol:SetPoint("TOPLEFT", 1, -HEAD_H)
    tabCol:SetPoint("BOTTOMLEFT", 1, 1)
    tabCol:SetWidth(TAB_W + PAD)
    local colBg = tabCol:CreateTexture(nil, "BACKGROUND", nil, 4)
    colBg:SetAllPoints()
    ns.UI.Gradient(colBg, "HORIZONTAL", 0, 0, 0, 0.55, 0, 0, 0, 0.35)
    local sep = tabCol:CreateTexture(nil, "ARTWORK")
    sep:SetWidth(1)
    sep:SetPoint("TOPRIGHT")
    sep:SetPoint("BOTTOMRIGHT")
    ns.UI.Gradient(sep, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0, C.violet[1], C.violet[2], C.violet[3], 0.6)

    content = CreateFrame("Frame", nil, main)
    content:SetPoint("TOPLEFT", tabCol, "TOPRIGHT", PAD, -4)
    content:SetSize(MIN_W, MIN_H)

    -- pages a plusieurs sections : feuille qui defile (molette ou poignee)
    scroll = CreateFrame("ScrollFrame", nil, content)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -14, 0)
    sheet = CreateFrame("Frame", nil, scroll)
    sheet:SetSize(MIN_W - 14, 10)
    scroll:SetScrollChild(sheet)
    track = CreateFrame("Frame", nil, content)
    track:SetPoint("TOPRIGHT", -4, -2)
    track:SetPoint("BOTTOMRIGHT", -4, 2)
    track:SetWidth(4)
    local tbg = track:CreateTexture(nil, "BACKGROUND")
    tbg:SetAllPoints()
    tbg:SetColorTexture(0, 0, 0, 0.45)
    thumb = CreateFrame("Frame", nil, track)
    thumb:SetWidth(4)
    thumb:EnableMouse(true)
    thumb:SetHitRectInsets(-6, -6, 0, 0)     -- 4 px a l ecran, plus large a la souris
    local ttex = thumb:CreateTexture(nil, "ARTWORK")
    ttex:SetAllPoints()
    ttex:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.9)
    thumb:SetScript("OnEnter", function() ttex:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1) end)
    thumb:SetScript("OnLeave", function() ttex:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.9) end)

    local function range() return math.max(0, sheet:GetHeight() - scroll:GetHeight()) end
    local function sync()
        local r = range()
        local th = track:GetHeight()
        if r <= 0 or th <= 0 then thumb:Hide() return end
        local h = math.max(24, th * scroll:GetHeight() / sheet:GetHeight())
        thumb:SetHeight(h)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(th - h) * (scroll:GetVerticalScroll() or 0) / r)
        thumb:Show()
    end
    local function scrollTo(v)
        scroll:SetVerticalScroll(math.max(0, math.min(range(), v)))
        sync()
    end
    scroll.ScrollTo, scroll.Sync = scrollTo, sync
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, d) scrollTo(self:GetVerticalScroll() - d * 50) end)
    scroll:SetScript("OnSizeChanged", function(_, w)
        sheet:SetWidth(w)
        if stack then stack() end
    end)
    thumb:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        local start, s = cy / self:GetEffectiveScale(), scroll:GetVerticalScroll()
        self:SetScript("OnUpdate", function()
            local _, y = GetCursorPosition()
            local free = track:GetHeight() - self:GetHeight()
            if free > 0 then scrollTo(s + (start - y / self:GetEffectiveScale()) * range() / free) end
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
end

-- Taille de la fenetre : fixe, sauf pour un panneau seul plus grand
fitMain = function()
    if not main then return end
    local w, h = MIN_W, MIN_H - HEAD_H - PAD
    h = math.max(h, tabsNeed or 0)
    if current then
        w = math.max(w, current:GetWidth())
        h = math.max(h, current:GetHeight())
    elseif currentPage and currentPage.width then
        w = math.max(w, currentPage.width + 30)
    end
    content:SetSize(w, h)
    main:SetSize(TAB_W + w + PAD * 3, h + HEAD_H + PAD)
end

function ns.PanelParent()
    if not main then buildMain() end
    return content
end

function ns.NewPanel(name, title, width, height)
    local parent = ns.PanelParent()
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(width, height)
    f:SetPoint("TOPLEFT")
    f.title = f:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(f.title, 15)
    f.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    f.title:SetJustifyH("LEFT")
    f.title:SetText((title or ""):match(" %- (.+)$") or title or "")
    -- souligne : violet qui s efface vers la droite
    f.titleLine = f:CreateTexture(nil, "ARTWORK")
    f.titleLine:SetHeight(1)
    ns.UI.Gradient(f.titleLine, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.8, C.violet[1], C.violet[2], C.violet[3], 0)
    f:SetScript("OnSizeChanged", function(self)
        if self == current then
            fitMain()
        elseif self:GetParent() == sheet and not stacking then
            -- une section change de taille (liste qui grandit...) : on reempile
            C_Timer.After(0, stack)
        end
    end)
    f:Hide()
    panels[name] = f
    return f
end

local function highlightTab()
    for _, t in ipairs(tabs) do
        local on = t.page == currentPage
        t.selected:SetShown(on)
        t.bar:SetShown(on)
        if on then
            t.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        else
            t.label:SetTextColor(C.text[1], C.text[2], C.text[3])
        end
    end
end

-- Titre ancre sur deux cotes avec une hauteur fixe, et reancre a chaque
-- affichage : en jeu, un titre ancre par un seul coin restait parfois sans
-- position calculee, donc invisible (constate sur Marchand, Reactifs, Persos).
local function placeTitle(panel)
    local t = panel.title
    if not t then return end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -6)
    t:SetHeight(20)
    t:SetWidth(math.max(40, (t:GetStringWidth() or 100) + 4))
    -- a quoi sert le module, en gris, a droite du titre
    local d = descs[panel:GetName() or ""]
    if d then
        if not panel.descText then
            panel.descText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            panel.descText:SetJustifyH("LEFT")
            panel.descText:SetWordWrap(false)
        end
        panel.descText:ClearAllPoints()
        panel.descText:SetPoint("LEFT", t, "RIGHT", 10, -1)
        -- titleReserve : place prise en haut a droite par le module (recherche...)
        panel.descText:SetWidth(math.max(10, panel:GetWidth() - t:GetWidth() - 18 - (panel.titleReserve or 0)))
        local ok, text = pcall(d)
        panel.descText:SetText(ok and text and (text:sub(1, 1):upper() .. text:sub(2)) or "")
    end
    if panel.titleLine then
        panel.titleLine:ClearAllPoints()
        panel.titleLine:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
        panel.titleLine:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -28)
    end
end

---------------------------------------------------------------------------
-- Pages a plusieurs sections : chaque panneau de module devient une carte,
-- empilee sous la precedente. Sa hauteur est celle de son contenu (le bas
-- de l element le plus bas), pas celle annoncee par le module.
---------------------------------------------------------------------------

local function measure(p)
    local top = p:GetTop()
    if not top then return p:GetHeight() end
    local low = top - 30
    local function see(o)
        if o ~= p.card and o:IsShown() then
            local b = o:GetBottom()
            if b and b < low then low = b end
        end
    end
    for _, o in ipairs({ p:GetChildren() }) do see(o) end
    for _, o in ipairs({ p:GetRegions() }) do see(o) end
    return math.floor(top - low + 10)
end

stack = function()
    local page = currentPage
    if stacking or current or not page or not page.list or not sheet then return end
    stacking = true
    local w = sheet:GetWidth() - 16
    local y = 4
    for _, p in ipairs(page.list) do
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", sheet, "TOPLEFT", 8, -y)
        p:SetWidth(w)
        placeTitle(p)
        local h = measure(p)
        if not p.card then
            p.card = p:CreateTexture(nil, "BACKGROUND", nil, -7)
            ns.UI.Gradient(p.card, "VERTICAL", 0, 0, 0, 0.38, 0, 0, 0, 0.22)
        end
        p.card:ClearAllPoints()
        p.card:SetPoint("TOPLEFT", p, "TOPLEFT", -6, 2)
        p.card:SetSize(w + 12, h + 2)
        p.card:Show()
        p.stackTop = y
        y = y + h + SECTION_GAP
    end
    sheet:SetHeight(math.max(1, y))
    stacking = false
    scroll.Sync()
end

local function showPage(page, focus)
    if not main then buildMain() end
    if results then results:Hide() end
    -- construire les sections pas encore ouvertes (sans les afficher seules)
    building = true
    for _, s in ipairs(page.sections) do
        if not panels[s.panelName] then
            local ok, err = pcall(s.build)
            if not ok then
                -- panneau casse : visible dans le chat (les erreurs Lua sont souvent masquees)
                ns.Say("|cffff4040" .. tostring(err) .. "|r")
                geterrorhandler()(err)
            end
        end
    end
    building = false
    local list = {}
    for _, s in ipairs(page.sections) do
        local p = panels[s.panelName]
        if p then
            p.naturalW = p.naturalW or p:GetWidth()
            table.insert(list, p)
        end
    end
    for _, p in pairs(panels) do p:Hide() end
    currentPage = page
    ns.root.lastPage = page.key
    main:Show()
    if #list == 1 and not page.scroll then
        -- un seul module : son panneau tel quel, la fenetre s adapte
        local p = list[1]
        scroll:Hide()
        track:Hide()
        p:SetParent(content)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT")
        if p.card then p.card:Hide() end
        placeTitle(p)
        current = p
        page.list = nil
        p:Show()
    else
        current = nil
        page.list = list
        page.width = 0
        for _, p in ipairs(list) do page.width = math.max(page.width, p.naturalW) end
        scroll:Show()
        track:Show()
        for _, p in ipairs(list) do
            p:SetParent(sheet)
            p:Show()
        end
    end
    highlightTab()
    fitMain()
    if page.list then
        stack()
        scroll.ScrollTo(focus and focus.stackTop and focus.stackTop - 4 or 0)
        -- les textes ont leur taille au rendu suivant : on reempile
        C_Timer.After(0, function()
            if currentPage ~= page then return end
            stack()
            if focus and focus.stackTop then scroll.ScrollTo(focus.stackTop - 4) end
        end)
    end
end

-- Les modules affichent leur panneau ainsi : on montre la page qui le
-- contient, defilee jusqu a lui
function ns.ShowPanel(panel)
    if building then return end
    if not main then buildMain() end
    ns.BuildTabs()
    local page = pageOf[panel:GetName() or ""]
    if page then
        showPage(page, panel)
    else
        for _, p in pairs(panels) do if p ~= panel then p:Hide() end end
        scroll:Hide()
        track:Hide()
        placeTitle(panel)
        current, currentPage = panel, nil
        main:Show()
        panel:Show()
        highlightTab()
        fitMain()
    end
end

local function addTab(page, label, icon)
    local b = CreateFrame("Button", nil, tabCol)
    b:SetSize(TAB_W, TAB_H)
    b.page = page
    -- choisi : degrade violet + barre d or a gauche
    b.selected = b:CreateTexture(nil, "BACKGROUND")
    b.selected:SetAllPoints()
    ns.UI.Gradient(b.selected, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.38, C.violet[1], C.violet[2], C.violet[3], 0)
    b.selected:Hide()
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(2)
    b.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    b.bar:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    ns.UI.Gradient(hl, "HORIZONTAL", 1, 1, 1, 0.10, 1, 1, 1, 0)
    -- icone dans un cadre sombre de 1 px
    local frame = b:CreateTexture(nil, "ARTWORK")
    frame:SetSize(TAB_H - 6, TAB_H - 6)
    frame:SetPoint("LEFT", 8, 0)
    frame:SetColorTexture(0, 0, 0, 1)
    local ic = b:CreateTexture(nil, "ARTWORK", nil, 1)
    ic:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    ic:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    ic:SetTexture(icon or "Interface\\Icons\\INV_Misc_Gear_01")
    if icon ~= ns.LOGO then ic:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("LEFT", frame, "RIGHT", 8, 0)
    b.label:SetPoint("RIGHT", -4, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    b.label:SetText(label)
    b:SetScript("OnClick", function() showPage(page) end)
    table.insert(tabs, b)
end

-- Echelle de toute l interface : CVar uiScale du jeu (0,64 a 1,15), et en
-- dessous (pixel parfait sur grand ecran) l echelle d UIParent, reposee a
-- chaque fois que le jeu la remet (changement d ecran, d echelle)
local scalePending, scaleTimer, applyingScale
function ns.CurrentUIScale()
    return UIParent:GetScale() or 1
end
function ns.PixelPerfectScale()
    local ok, _, h = pcall(GetPhysicalScreenSize)
    if ok and type(h) == "number" and h > 0 then
        return math.max(0.4, math.min(1.15, 768 / h))
    end
    return 1
end
local function applyUIScale()
    local s = ns.root and ns.root.uiScale
    if not s then return end
    if InCombatLockdown() then scalePending = true return end
    scalePending = false
    applyingScale = true
    if s >= 0.64 then
        pcall(SetCVar, "useUiScale", "1")
        pcall(SetCVar, "uiScale", tostring(s))
    end
    if math.abs((UIParent:GetScale() or 1) - s) > 0.001 then pcall(UIParent.SetScale, UIParent, s) end
    applyingScale = false
end
ns.ApplyUIScale = applyUIScale
-- later : curseur, applique quand on le lache (sinon la fenetre bouge sous la souris)
function ns.SetUIScale(s, later)
    if s then s = math.floor(math.max(0.4, math.min(1.15, s)) * 100 + 0.5) / 100 end
    local was = ns.root.uiScale
    if s and not was then
        -- reglage du jeu avant CorpUI, rendu si on decoche
        local okU, use = pcall(GetCVar, "useUiScale")
        local okS, val = pcall(GetCVar, "uiScale")
        ns.root.uiScaleOrig = { use = okU and use or "0", value = okS and val or "1" }
    end
    ns.root.uiScale = s
    if not s then
        if was then
            local o = ns.root.uiScaleOrig or { use = "0", value = "1" }
            pcall(SetCVar, "useUiScale", o.use)
            pcall(SetCVar, "uiScale", o.value)
            local back = o.use == "1" and tonumber(o.value) or nil
            if back then pcall(UIParent.SetScale, UIParent, back) end
            ns.root.uiScaleOrig = nil
        end
        return
    end
    if scaleTimer then scaleTimer:Cancel() end
    if later then
        scaleTimer = C_Timer.NewTimer(0.6, applyUIScale)
    else
        applyUIScale()
    end
end
do
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and not scalePending then return end
        if applyingScale then return end
        applyUIScale()
    end)
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        pcall(f.RegisterEvent, f, e)
    end
end

-- Onglet General : langue, minicarte, rechargement
local general
local function buildGeneral()
    general = ns.NewPanel("CorpUIGeneral", L.TAB_GENERAL, 440, 450)
    local update      -- pastilles du theme (defini plus bas)
    local form = ns.UI.Form(general, -40, function() update() end)

    -- langue : liste deroulante (automatique, puis les langues connues)
    form:Header(L.GEN_LANG)
    local langs, shortOf = { { value = "auto", text = L.GEN_AUTO } }, { auto = "auto" }
    for _, lang in ipairs(ns.LANGUAGES) do
        shortOf[lang.code] = lang.short
        table.insert(langs, { value = lang.code, text = lang.name })
    end
    form:Select(nil, function() return langs end, function() return ns.root.lang or "auto" end,
        function(v) ns.LangCommand(shortOf[v] or v) end, 200)
    local hint = general:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", general, "TOPLEFT", 8, form.y + 2)
    hint:SetText(L.GEN_RELOAD_HINT)
    form:Gap(16)
    -- bouton securise : ancre sur le panneau, jamais sur un texte
    local reload = ns.UI.ReloadButton(general, L.GEN_RELOAD, 160)
    reload:SetPoint("TOPLEFT", general, "TOPLEFT", 8, form.y)
    -- assistant d installation (Installation/Assistant.lua)
    local wizard = ns.UI.Button(general, L.GEN_WIZARD, 120, function() if ns.OpenInstall then ns.OpenInstall() end end)
    wizard:SetPoint("LEFT", reload, "RIGHT", 6, 0)
    form:Gap(32)
    -- une case par ligne : le libelle "deverrouiller" est long
    form:Check(L.GEN_MINIMAP, function() return not ns.root.minimap.hide end, function(v)
        ns.root.minimap.hide = not v
        ns.Changed()
    end)
    general.unlock = form:Check(L.GEN_UNLOCK, function() return ns.moversShown end, function(v) ns.SetMoversShown(v) end)
    form:Gap(6)

    -- echelle de toute l interface (celle du jeu comprise)
    form:Header(L.GEN_SCALE)
    form:Check(L.GEN_SCALE_ON, function() return ns.root.uiScale ~= nil end, function(v)
        ns.SetUIScale(v and (ns.root.uiScale or ns.CurrentUIScale()) or nil)
    end)
    form:Columns(2)
    local scaleSl = form:Number(L.GEN_SCALE_VALUE, function() return math.floor((ns.root.uiScale or ns.CurrentUIScale()) * 100 + 0.5) end,
        function(v) ns.SetUIScale(v / 100, true) end, 40, 115, 1)
    local pp = ns.UI.Button(general, L.GEN_SCALE_PIXEL, 120, function()
        ns.SetUIScale(ns.PixelPerfectScale())
        form:Refresh()
    end)
    pp:SetPoint("TOPLEFT", general, "TOPLEFT", 8 + 220, form.y - 14)
    form:Cell(44)
    form:EndColumns()
    table.insert(form.refreshers, function()
        local on = ns.root.uiScale ~= nil
        scaleSl:SetAlpha(on and 1 or 0.5)
    end)
    local scaleHint = general:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scaleHint:SetPoint("TOPLEFT", general, "TOPLEFT", 8, form.y + 2)
    scaleHint:SetWidth(420)
    scaleHint:SetJustifyH("LEFT")
    scaleHint:SetText(L.GEN_SCALE_HINT)
    form:Gap(26)

    -- couleur du theme : une pastille par accent, la choisie entouree d or
    -- style : classique ou moderne (plat, couleur de classe, police Saira)
    local styleSel = form:Cycle(L.GEN_STYLE, { "classique", "moderne" },
        { classique = L.STYLE_CLASSIC, moderne = L.STYLE_MODERN },
        function() return ns.root.style or "classique" end,
        function(v) ns.SetStyle(v) end)
    local styleHint = general:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    styleHint:SetPoint("LEFT", styleSel, "RIGHT", 8, 0)
    general.styleHint = styleHint
    -- disposition des maquettes (Disposition.lua) et retour en arriere
    if ns.ModernLayout then
        local lay = ns.UI.Button(general, L.LAYOUT_APPLY, 170, function()
            ns.ModernLayout.Apply()
            form.Changed()
        end)
        lay:SetPoint("TOPLEFT", general, "TOPLEFT", 8, form.y - 2)
        local back = ns.UI.Button(general, L.LAYOUT_RESTORE, 170, function()
            ns.ModernLayout.Restore()
            form.Changed()
        end)
        back:SetPoint("LEFT", lay, "RIGHT", 6, 0)
        form.y = form.y - 28
        local layHint = general:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        layHint:SetPoint("TOPLEFT", general, "TOPLEFT", 8, form.y)
        layHint:SetWidth(420)
        layHint:SetJustifyH("LEFT")
        layHint:SetText(L.LAYOUT_HINT)
        form.y = form.y - 30
        table.insert(form.refreshers, function() back:SetEnabled(ns.ModernLayout.HasBackup()) end)
    end
    form:Gap(4)
    local themeTitle = form:Header(L.GEN_THEME)
    local themeHint = general:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    themeHint:SetPoint("LEFT", themeTitle, "RIGHT", 8, 0)
    general.swatches = {}
    for i, t in ipairs(ns.THEMES) do
        local s = CreateFrame("Button", nil, general)
        s:SetSize(30, 18)
        s:SetPoint("TOPLEFT", general, "TOPLEFT", 10 + (i - 1) * 36, form.y - 2)
        s.ring = s:CreateTexture(nil, "BACKGROUND")
        s.ring:SetPoint("TOPLEFT", -2, 2)
        s.ring:SetPoint("BOTTOMRIGHT", 2, -2)
        s.ring:SetColorTexture(ns.COLORS.gold[1], ns.COLORS.gold[2], ns.COLORS.gold[3], 1)
        local edge = s:CreateTexture(nil, "BORDER")
        edge:SetAllPoints()
        edge:SetColorTexture(0, 0, 0, 1)
        local c = ns.ThemeColor(t.key)
        local fill = s:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        if t.bg then
            -- theme sombre : du noir a l anthracite
            ns.UI.Gradient(fill, "VERTICAL", 0.02, 0.02, 0.022, 1, 0.30, 0.30, 0.33, 1)
        else
            ns.UI.Gradient(fill, "VERTICAL", c[1] * 0.45, c[2] * 0.45, c[3] * 0.45, 1, c[1], c[2], c[3], 1)
        end
        s.key = t.key
        s:SetScript("OnEnter", function(self)
            local tip = ns.Tooltip(self, "ANCHOR_TOP")
            tip:AddLine(L["THEME_" .. string.upper(t.key)])
            tip:Show()
        end)
        s:SetScript("OnLeave", ns.HideTooltip)
        s:SetScript("OnClick", function()
            ns.root.theme = t.key
            form.Changed()
        end)
        general.swatches[i] = s
    end
    general.themeHint = themeHint
    form:Gap(30)

    -- police (Polices.lua) : liste deroulante, ajout d une police
    local fontHint = ns.BuildFontOptions and ns.BuildFontOptions(general, nil, form)
    local about = general:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    if fontHint then
        about:SetPoint("TOPLEFT", fontHint, "BOTTOMLEFT", 0, -14)
    else
        about:SetPoint("TOPLEFT", general, "TOPLEFT", 8, form.y - 6)
    end
    about:SetText(string.format(L.GEN_ABOUT, ns.VERSION))
    general:SetHeight(math.floor(110 - form.y))

    update = function()
        local chosen = ns.root.theme or "violet"
        for _, s in ipairs(general.swatches) do s.ring:SetShown(s.key == chosen) end
        -- choix different de la couleur en cours : il faut recharger
        general.themeHint:SetText(chosen ~= ns.COLORS.themeKey and L.GEN_THEME_HINT or "")
        general.styleHint:SetText(((ns.root.style == "moderne") ~= (ns.MODERN and true or false)) and L.GEN_THEME_HINT or "")
    end
    general:SetScript("OnShow", function()
        update()
        form:Refresh()
    end)
end

local function openGeneral()
    if not general then buildGeneral() end
    ns.ShowPanel(general)
end


-- intertitre de la colonne (Interface, Combat, Outils)
local function addHeader(label)
    local h = CreateFrame("Frame", nil, tabCol)
    h:SetSize(TAB_W, CAT_H)
    h.label = h:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(h.label, 10)
    h.label:SetPoint("BOTTOMLEFT", 8, 5)
    h.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    h.label:SetText(string.upper(L[label] or label))
    h.line = h:CreateTexture(nil, "ARTWORK")
    h.line:SetPoint("BOTTOMLEFT", 6, 1)
    h.line:SetPoint("BOTTOMRIGHT", -6, 1)
    h.line:SetHeight(1)
    ns.UI.Gradient(h.line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.45, C.gold[1], C.gold[2], C.gold[3], 0)
    return h
end

---------------------------------------------------------------------------
-- Recherche dans les options : tous les textes des panneaux (libelles,
-- intertitres, cases) sont releves ; un clic sur un resultat ouvre la page,
-- la fait defiler jusqu a l option et la fait clignoter en or.
---------------------------------------------------------------------------
local SEARCH_H, ROW_H = 30, 22
local flash
local searchTexts           -- { fs, panel, page }
local hits, hitOffset = {}, 0

-- texte comparable : sans couleurs ni icones, en minuscules
local function plain(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("\239\188\154", ":")
    return s:lower()
end

local function readText(fs)
    local ok, t = pcall(fs.GetText, fs)
    if not ok or type(t) ~= "string" or t == "" then return nil end
    if issecretvalue and issecretvalue(t) then return nil end
    return t
end

-- visible une fois le panneau affiche (les variantes cachees sont ignorees)
-- Un sous-panneau cache qui porte cuiReveal (editeur des cadres : un
-- sous-panneau par cadre) compte comme visible : renvoie aussi ce
-- sous-panneau, que l ouverture du resultat montrera.
local function shownIn(r, panel)
    local f, variant = r, nil
    while f and f ~= panel do
        if not f:IsShown() then
            if f.cuiReveal and not variant then variant = f else return false end
        end
        f = f:GetParent()
    end
    if f ~= panel then return false end
    return true, variant
end

local function collect(frame, panel, page, out)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:GetObjectType() == "FontString" and r ~= panel.title then
            table.insert(out, { fs = r, panel = panel, page = page })
        end
    end
    for _, c in ipairs({ frame:GetChildren() }) do
        if c:GetObjectType() ~= "EditBox" then collect(c, panel, page, out) end
    end
end

-- construit toutes les sections pas encore ouvertes, puis releve leurs textes
local function buildIndex()
    building = true
    for _, t in ipairs(tabs) do
        for _, s in ipairs(t.page.sections) do
            if not panels[s.panelName] then
                local ok, err = pcall(s.build)
                if not ok then geterrorhandler()(err) end
            end
        end
    end
    building = false
    searchTexts = {}
    for _, t in ipairs(tabs) do
        for _, s in ipairs(t.page.sections) do
            local p = panels[s.panelName]
            if p then
                for _, r in ipairs({ p:GetRegions() }) do
                    if r == p.title then table.insert(searchTexts, { fs = r, panel = p, page = t.page, isTitle = true }) end
                end
                collect(p, p, t.page, searchTexts)
            end
        end
    end
end

local function pageName(page)
    for _, t in ipairs(tabs) do
        if t.page == page then return t.label:GetText() or "" end
    end
    return ""
end

-- clignotement d or autour d un texte
local function flashOn(fs)
    if not flash then
        flash = CreateFrame("Frame", nil, main)
        flash:SetFrameStrata("TOOLTIP")
        local tex = flash:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        ns.UI.Gradient(tex, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.45, C.gold[1], C.gold[2], C.gold[3], 0)
        local line = flash:CreateTexture(nil, "OVERLAY", nil, 1)
        line:SetPoint("TOPLEFT")
        line:SetPoint("BOTTOMLEFT")
        line:SetWidth(2)
        line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    end
    flash:ClearAllPoints()
    flash:SetPoint("TOPLEFT", fs, "TOPLEFT", -6, 4)
    flash:SetPoint("BOTTOMLEFT", fs, "BOTTOMLEFT", -6, -4)
    flash:SetWidth(math.max(160, (fs:GetStringWidth() or 0) + 60))
    local t = 0
    flash:SetScript("OnUpdate", function(self, el)
        t = t + el
        if t > 2.4 or not fs:IsVisible() then self:Hide() self:SetScript("OnUpdate", nil) return end
        self:SetAlpha(0.35 + 0.65 * math.abs(math.cos(t * 3.2)))
    end)
    flash:Show()
end

local function openHit(h)
    results:Hide()
    searchBox:ClearFocus()
    -- reglage d un autre cadre de l editeur : on le choisit d abord
    if h.variant and h.variant.cuiReveal then h.variant.cuiReveal() end
    showPage(h.page, h.panel)
    -- apres le reempilement de showPage (meme image, enregistre avant)
    C_Timer.After(0, function()
        if currentPage ~= h.page then return end
        if h.page.list and sheet:GetTop() and h.fs:GetTop() then
            scroll.ScrollTo(sheet:GetTop() - h.fs:GetTop() - 60)
        end
        if h.fs:IsVisible() then flashOn(h.fs) end
    end)
end

local function rowCount()
    return math.max(4, math.floor((results:GetHeight() - 34) / ROW_H))
end

local function drawResults()
    local n = rowCount()
    hitOffset = math.max(0, math.min(hitOffset, #hits - n))
    for i, row in ipairs(results.rows) do
        local h = hits[i + hitOffset]
        if h and i <= n then
            row.hit = h
            row.text:SetText(h.text)
            row.where:SetText(h.where)
            row:Show()
        else
            row:Hide()
        end
    end
    if #hits == 0 then
        results.count:SetText(L.SEARCH_NONE)
    else
        results.count:SetText(string.format(L.SEARCH_COUNT, #hits))
    end
end

local function buildResults()
    results = CreateFrame("Frame", nil, main, "BackdropTemplate")
    results:SetPoint("TOPLEFT", content, "TOPLEFT", -PAD / 2, 4)
    results:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -1, 1)
    results:SetFrameLevel(main:GetFrameLevel() + 500)
    results:EnableMouse(true)
    results:EnableMouseWheel(true)
    ns.UI.SetBackdrop(results, 1)
    results:SetBackdropBorderColor(0, 0, 0, 0)
    -- fond plein : la page dessous ne doit pas transparaitre
    local solid = results:CreateTexture(nil, "BACKGROUND", nil, -1)
    solid:SetAllPoints()
    solid:SetColorTexture(C.bg[1] * 0.6, C.bg[2] * 0.6, C.bg[3] * 0.6, 1)
    results.count = results:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(results.count, 13)
    results.count:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    results.count:SetPoint("TOPLEFT", 10, -8)
    results.rows = {}
    for i = 1, 40 do
        local row = CreateFrame("Button", nil, results)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 6, -30 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", -10, 0)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0)
        row.where = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.where:SetPoint("RIGHT", -4, 0)
        row.where:SetJustifyH("RIGHT")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetPoint("RIGHT", row.where, "LEFT", -10, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(self) if self.hit then openHit(self.hit) end end)
        row:Hide()
        results.rows[i] = row
    end
    results:SetScript("OnMouseWheel", function(_, d)
        hitOffset = hitOffset - d * 3
        drawResults()
    end)
    results:Hide()
end

-- synonymes (L.SEARCH_SYNONYMS : groupes separes par ";", termes par ",")
local synGroups
local function expand(text)
    if not synGroups then
        synGroups = {}
        for group in (L.SEARCH_SYNONYMS or ""):gmatch("[^;]+") do
            local g = {}
            for term in group:gmatch("[^,]+") do
                term = plain(strtrim(term))
                if term ~= "" then table.insert(g, term) end
            end
            table.insert(synGroups, g)
        end
    end
    local terms, have = { text }, { [text] = true }
    for _, g in ipairs(synGroups) do
        local hit = false
        for _, term in ipairs(g) do
            -- debut d un synonyme tape ("histo"), ou synonyme contenu dans la saisie
            if (#text >= 3 and term:find(text, 1, true)) or (#term >= 3 and text:find(term, 1, true)) then hit = true break end
        end
        if hit then
            for _, term in ipairs(g) do
                if not have[term] then have[term] = true table.insert(terms, term) end
            end
        end
    end
    return terms
end

-- un terme court (pv, cd, xp) doit etre un mot entier
local function matches(p, terms)
    if p:find(terms[1], 1, true) then return true end
    for i = 2, #terms do
        local term = terms[i]
        if #term <= 2 then
            if p:find("%f[%w]" .. term .. "%f[%W]") then return true end
        elseif p:find(term, 1, true) then
            return true
        end
    end
    return false
end

local function runSearch(text)
    text = plain(strtrim(text or ""))
    if text == "" or not tabs[1] then
        if results then results:Hide() end
        return
    end
    local terms = expand(text)
    if not searchTexts then buildIndex() end
    if not results then buildResults() end
    wipe(hits)
    hitOffset = 0
    local seen = {}
    -- les pages d abord
    for _, t in ipairs(tabs) do
        local name = t.label:GetText() or ""
        if matches(plain(name), terms) then
            table.insert(hits, { direct = plain(name):find(text, 1, true) ~= nil, text = "|cffffd100" .. name .. "|r", where = "", page = t.page, panel = nil, fs = t.label })
        end
    end
    for _, e in ipairs(searchTexts) do
        local s = readText(e.fs)
        local visible, variant = false, nil
        if s and #s > 1 then
            if e.isTitle then visible = true else visible, variant = shownIn(e.fs, e.panel) end
        end
        if visible then
            local p = plain(s)
            local key = tostring(e.panel) .. tostring(variant) .. p
            if not seen[key] and matches(p, terms) then
                seen[key] = true
                local where = pageName(e.page)
                local title = e.panel.title and readText(e.panel.title)
                if title and #e.page.sections > 1 and not e.isTitle then where = where .. " › " .. title end
                if variant and variant.cuiLabel then where = where .. " › " .. variant.cuiLabel end
                table.insert(hits, { direct = p:find(text, 1, true) ~= nil, text = s:gsub("[\r\n]+", " "), where = where,
                    page = e.page, panel = e.panel, fs = e.fs, variant = variant })
            end
        end
    end
    -- correspondances exactes d abord, puis les synonymes (ordre garde)
    for i, h in ipairs(hits) do h.order = i end
    table.sort(hits, function(a, b)
        if a.direct ~= b.direct then return a.direct end
        return a.order < b.order
    end)
    results:Show()
    drawResults()
end

local function buildSearch()
    local box = CreateFrame("EditBox", nil, tabCol)
    box:SetSize(TAB_W - 4, 22)
    box:SetPoint("TOPLEFT", tabCol, "TOPLEFT", PAD / 2 + 2, -8)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(22, 20, 0, 0)
    box:SetMaxLetters(40)
    ns.UI.Skin(box, 0.8)
    local glass = box:CreateTexture(nil, "OVERLAY")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", 5, 0)
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 22, 0)
    hint:SetText(L.SEARCH)
    local clear = CreateFrame("Button", nil, box)
    clear:SetSize(16, 16)
    clear:SetPoint("RIGHT", -3, 0)
    local x = clear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    x:SetPoint("CENTER")
    x:SetText("×")
    clear:SetScript("OnClick", function() box:SetText("") box:ClearFocus() end)
    clear:Hide()
    local function sync()
        local empty = (box:GetText() or "") == ""
        hint:SetShown(empty and not box:HasFocus())
        clear:SetShown(not empty)
    end
    box:SetScript("OnTextChanged", function(self)
        sync()
        runSearch(self:GetText())
    end)
    box:SetScript("OnEditFocusGained", function()
        -- les listes changent : on releve les textes a chaque fois
        searchTexts = nil
        sync()
        if (box:GetText() or "") ~= "" then runSearch(box:GetText()) end
    end)
    box:SetScript("OnEditFocusLost", sync)
    box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self)
        if hits[1] and results and results:IsShown() then openHit(hits[1]) else self:ClearFocus() end
    end)
    searchBox = box
end

ns.SearchOptions = function(text)
    if not main then buildMain() end
    ns.BuildTabs()
    searchBox:SetText(text or "")
end

-- Les onglets sont crees une fois, quand tous les modules sont enregistres
local function buildTabs()
    if #tabs > 0 then return end
    if not main then buildMain() end
    if not searchBox then buildSearch() end
    local byCmd, used = {}, {}
    for _, m in ipairs(ns.modules) do
        if m.Open and m.panelName then byCmd[m.command] = m end
        if m.desc and m.panelName then descs[m.panelName] = m.desc end
    end
    -- pages de la liste, puis une page par module non range
    local list = {}
    for _, p in ipairs(PAGES) do table.insert(list, p) end
    for _, m in ipairs(ns.modules) do
        local listed = false
        for _, p in ipairs(PAGES) do
            for _, c in ipairs(p.cmds or {}) do if c == m.command then listed = true end end
        end
        if not listed and m.Open and m.panelName then table.insert(list, { key = m.command, cmds = { m.command } }) end
    end

    local y = -8 - SEARCH_H
    for _, p in ipairs(list) do
        if p.cat then
            local h = addHeader(p.cat)
            h:SetPoint("TOPLEFT", tabCol, "TOPLEFT", PAD / 2, y - 4)
            y = y - CAT_H - 6
        else
            p.sections = {}
            local first
            for _, c in ipairs(p.cmds) do
                if c == "@general" then
                    table.insert(p.sections, { panelName = "CorpUIGeneral", build = function() if not general then buildGeneral() end end })
                    pageOf.CorpUIGeneral = p
                elseif byCmd[c] then
                    local m = byCmd[c]
                    first = first or m
                    table.insert(p.sections, { panelName = m.panelName, build = m.Open })
                    pageOf[m.panelName] = p
                end
            end
            if #p.sections > 0 then
                local label = (p.label and L[p.label]) or (first and first.title and first.title()) or p.key
                addTab(p, label, p.icon or (first and first.icon))
                tabs[#tabs]:SetPoint("TOPLEFT", tabCol, "TOPLEFT", PAD / 2, y)
                y = y - TAB_H - 2
            end
        end
    end
    tabsNeed = -y + 8
end

ns.BuildTabs = buildTabs

function ns.ToggleMain()
    if not main then buildMain() end
    buildTabs()
    if main:IsShown() then
        main:Hide()
        return
    end
    -- rouvrir la derniere page consultee
    local last = ns.root.lastPage
    for _, t in ipairs(tabs) do
        if t.page.key == last then
            showPage(t.page)
            return
        end
    end
    showPage(tabs[1].page)
end

---------------------------------------------------------------------------
-- Bouton de minicarte
--   clic gauche : menu des outils, clic droit : Alt du premier module
---------------------------------------------------------------------------

local mini

local function placeMini()
    local angle = math.rad(ns.root.minimap.angle or 200)
    local r = (Minimap:GetWidth() / 2) + 8
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function createMini()
    mini = CreateFrame("Button", "CorpUIMinimapButton", Minimap)
    -- carre plat aux couleurs du theme (la minicarte est carree)
    mini:SetSize(26, 26)
    mini:SetFrameStrata("MEDIUM")
    mini:SetFrameLevel(8)
    mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mini:RegisterForDrag("LeftButton")
    ns.UI.Skin(mini, 0.95, true)

    local icon = mini:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexture(ns.MEDIA .. "logo64")
    local hl = mini:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(ns.COLORS.violet[1], ns.COLORS.violet[2], ns.COLORS.violet[3], 0.25)

    mini:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local m = ns.modules[1]
            if m and m.Alt then m.Alt() end
        else
            ns.ToggleMain()
        end
    end)
    mini:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.root.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            placeMini()
        end)
    end)
    mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mini:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self)
        t:AddLine(ns.TITLE)
        t:AddLine(L.MINI_HUB, 1, 1, 1)
        t:AddLine(L.MINI_RIGHT, 1, 1, 1)
        t:AddLine(L.MINI_DRAG, 0.6, 0.6, 0.6)
        t:Show()
    end)
    mini:SetScript("OnLeave", ns.HideTooltip)
    -- liseré dore au survol (apres SetScript, qui effacerait le crochet)
    mini:HookScript("OnEnter", function(self) self.cuiBorder:SetColorTexture(ns.COLORS.gold[1], ns.COLORS.gold[2], ns.COLORS.gold[3], 1) end)
    mini:HookScript("OnLeave", function(self) ns.UI.ResetBorder(self) end)
    placeMini()
end

ns.Listen(function()
    if mini then mini:SetShown(not ns.root.minimap.hide) end
end)

---------------------------------------------------------------------------
-- Evenements du socle
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON_NAME then
        ns.InitRoot()
    elseif event == "PLAYER_LOGIN" then
        ns.InitRoot()
        -- Reprise de HystéTools (ancien nom), une seule fois : quand les deux
        -- addons sont charges ensemble, ses reglages sont en memoire. Copie
        -- profonde, car HystéTools continue de modifier ses propres tables.
        local old = _G.HysteToolsDB
        if type(old) == "table" and not ns.root.migratedFromHysteTools then
            local function copy(v)
                if type(v) ~= "table" then return v end
                local t = {}
                for k, x in pairs(v) do t[k] = copy(x) end
                return t
            end
            for k in pairs(ns.root) do ns.root[k] = nil end
            for k, v in pairs(old) do ns.root[k] = copy(v) end
            ns.root.migratedFromHysteTools = true
            ns.Say(L.MIGRATED)
        end
        local ok, err = pcall(createMini)
        if not ok then geterrorhandler()(err) end
        for _, fn in ipairs(ns.inits) do
            ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
        ns.Changed()
    end
end)
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
