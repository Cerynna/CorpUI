--[[--------------------------------------------------------------------------
    CorpUI - module Infos (barre d informations)
    Une barre de textes, mise a jour chaque seconde :
      or, places libres dans les sacs, durabilite de l equipement (la plus
      basse), images par seconde, latence (domicile / monde), heure,
      coordonnees, amis et membres de guilde en ligne.
    Reglages : infos affichees et leur ordre, hauteur, taille du texte,
    espacement, largeur (auto ou fixe) et alignement, fond et son opacite,
    separateurs, visible au survol seulement, echelle.
    Cadre ordinaire, deplacable avec "Deverrouiller l interface".
    Clics et infobulles : un petit bouton SECURISE transparent par info,
    enfant d UIParent (pas de la barre : la barre change de largeur chaque
    seconde, meme en combat). Il est place hors combat sur le texte, avec
    des coordonnees calculees, et replace a la sortie du combat. Le clic
    "clique" le bouton de Blizzard voulu (type="click"), sans appeler de
    fonction de Blizzard depuis l addon.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local ITEMS = { "gold", "bags", "dur", "fps", "lat", "time", "coords", "friends", "guild" }
local DEFAULT_ON = { gold = true, bags = true, dur = true, fps = true, lat = true, time = true }
local ALIGNS = { "left", "center", "spread" }
local PAD = 8

local DEFAULTS = {
    enabled = true, scale = 1, height = 20, fontSize = 11, spacing = 18,
    width = 0, align = "center", backdrop = true, alpha = 85, separators = false, mouseover = false,
    clicks = true, tooltips = true,
}

local db
local bar
local texts, seps = {}, {}
local spots = {}        -- position de chaque texte affiche : { x, w } dans la barre
local hot = {}          -- boutons securises par info

local issecret = issecretvalue or function() return false end
local unpack = unpack or table.unpack

-- appel protege ; les valeurs secretes sont remplacees par nil
local function call(fn, ...)
    if type(fn) ~= "function" then return end
    local r = { n = 0 }
    local function pack(...) r.n = select("#", ...) for i = 1, r.n do r[i] = (select(i, ...)) end end
    pack(pcall(fn, ...))
    if not r[1] then return end
    for i = 2, r.n do if issecret(r[i]) then r[i] = nil end end
    return unpack(r, 2, r.n)
end

local function clean(v)
    if v == nil or issecret(v) then return nil end
    return v
end

local function money()
    local m = call(GetMoney)
    if type(m) == "number" then return m end
end

---------------------------------------------------------------------------
-- Valeurs : libelle en gris du theme, valeur en blanc (ou en couleur d etat)
---------------------------------------------------------------------------

local function grey(t)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(C.text[1] * 255), math.floor(C.text[2] * 255), math.floor(C.text[3] * 255), t)
end
local function white(t) return "|cffffffff" .. t .. "|r" end

local function bags()
    local free, total = 0, 0
    local freeFn = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    for _, b in ipairs(ns.PlayerBags()) do
        total = total + ns.BagSlots(b)
        if freeFn then
            local ok, n = pcall(freeFn, b)
            free = free + ((ok and n) or 0)
        end
    end
    return free, total
end

local function durability()
    local low
    for slot = 1, 18 do
        local ok, cur, max = pcall(GetInventoryItemDurability, slot)
        if ok and cur and max and max > 0 then
            local p = cur / max * 100
            if not low or p < low then low = p end
        end
    end
    return low
end

local function color(p)
    if p < 25 then return "|cffff4040" end
    if p < 50 then return "|cffffd100" end
    return "|cff80ff80"
end

local VALUE = {
    gold = function() return ns.FormatMoney(GetMoney()) end,
    bags = function()
        local free, total = bags()
        local p = total > 0 and free / total * 100 or 100
        return string.format("%s %s%d|r%s", grey(L.INFO_BAGS), color(p), free, grey("/" .. total))
    end,
    dur = function()
        local p = durability()
        if not p then return grey(L.INFO_DUR .. " -") end
        return string.format("%s %s%d%%|r", grey(L.INFO_DUR), color(p), math.floor(p + 0.5))
    end,
    fps = function() return white(math.floor(GetFramerate() + 0.5)) .. " " .. grey(L.INFO_FPS) end,
    lat = function()
        local _, _, home, world = GetNetStats()
        return white((home or 0) .. " / " .. (world or 0)) .. " " .. grey("ms")
    end,
    time = function() return white(date("%H:%M")) end,
    coords = function()
        local map = C_Map and C_Map.GetBestMapForUnit("player")
        local pos = map and C_Map.GetPlayerMapPosition(map, "player")
        local x, y
        if pos then x, y = pos:GetXY() end
        if not x or not y or (x == 0 and y == 0) then return grey("-, -") end
        return white(string.format("%.1f, %.1f", x * 100, y * 100))
    end,
    friends = function()
        local n = C_FriendList and C_FriendList.GetNumOnlineFriends and C_FriendList.GetNumOnlineFriends() or 0
        return grey(L.INFO_FRIENDS) .. " " .. white(n or 0)
    end,
    guild = function()
        if not IsInGuild() then return grey(L.INFO_GUILD .. " -") end
        -- 2e valeur : membres en ligne (la liste est demandee au serveur
        -- regulierement, voir plus bas : sans cela le jeu repond 0)
        local ok, _, online = pcall(GetNumGuildMembers)
        if not ok or issecret(online) or type(online) ~= "number" then online = 0 end
        return grey(L.INFO_GUILD) .. " " .. white(online)
    end,
}

---------------------------------------------------------------------------
-- Or de la session
---------------------------------------------------------------------------

local session = { gain = 0, loss = 0 }

local function trackMoney()
    local m = money()
    if not m then return end
    if session.last then
        local d = m - session.last
        if d > 0 then session.gain = session.gain + d elseif d < 0 then session.loss = session.loss - d end
    end
    session.last = m
end

---------------------------------------------------------------------------
-- Infobulles detaillees
---------------------------------------------------------------------------

local MAXLINES = 25
local TITLE = { 1, 0.82, 0 }

local function title(t, text) t:AddLine(text, TITLE[1], TITLE[2], TITLE[3]) end
local function pair(t, a, b) t:AddDoubleLine(a, b, C.text[1], C.text[2], C.text[3], 1, 1, 1) end
local function classHex(class)
    if class and ns.ClassHex then
        local ok, h = pcall(ns.ClassHex, class)
        if ok and type(h) == "string" then return h end
    end
    return "|cffffffff"
end
local function signed(v)
    if v < 0 then return "|cffff6060-|r" .. ns.FormatMoney(-v) end
    return "|cff60ff60+|r" .. ns.FormatMoney(v)
end

local TIP = {}

TIP.gold = function(t)
    title(t, L.INFO_GOLD_NAME)
    local me = ns.CharKey and ns.CharKey()
    local cur = money()
    local realm = call(GetRealmName)
    local list, total = {}, 0
    local alts = ns.root and ns.root.alts
    if type(alts) == "table" then
        for key, d in pairs(alts) do
            if type(d) == "table" and type(d.money) == "number" then
                local m = (key == me and cur) or d.money
                table.insert(list, { name = d.name or key, realm = d.realm, class = d.class, money = m })
            end
        end
    end
    if me and cur and not (type(alts) == "table" and alts[me]) then
        local _, class = call(UnitClass, "player")
        table.insert(list, { name = call(UnitName, "player") or me, realm = realm, class = class, money = cur })
    end
    table.sort(list, function(a, b) return a.money > b.money end)
    for i, c in ipairs(list) do
        total = total + c.money
        if i <= MAXLINES then
            local name = classHex(c.class) .. tostring(c.name) .. "|r"
            if c.realm and realm and c.realm ~= realm then name = name .. grey(" - " .. c.realm) end
            pair(t, name, ns.FormatMoney(c.money))
        end
    end
    if #list > MAXLINES then t:AddLine(string.format(L.INFO_TIP_MORE, #list - MAXLINES), C.text[1], C.text[2], C.text[3]) end
    if #list > 1 then pair(t, L.INFO_TIP_TOTAL, ns.FormatMoney(total)) end
    t:AddLine(" ")
    title(t, L.INFO_TIP_SESSION)
    pair(t, L.INFO_TIP_GAINED, ns.FormatMoney(session.gain))
    pair(t, L.INFO_TIP_SPENT, ns.FormatMoney(session.loss))
    pair(t, L.INFO_TIP_NET, signed(session.gain - session.loss))
end

TIP.bags = function(t)
    title(t, L.INFO_BAGS_NAME)
    local freeFn = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    local nameFn = (C_Container and C_Container.GetBagName) or GetBagName
    for _, b in ipairs(ns.PlayerBags()) do
        local size = ns.BagSlots(b)
        if size > 0 then
            local free = call(freeFn, b) or 0
            local name = call(nameFn, b)
            if type(name) ~= "string" then name = "#" .. b end
            local p = free / size * 100
            pair(t, name, string.format("%s%d|r/%d", color(p), free, size))
        end
    end
end

-- noms des emplacements (globales de Blizzard, en lecture)
local SLOTNAMES = {
    [1] = "HEADSLOT", [3] = "SHOULDERSLOT", [5] = "CHESTSLOT", [6] = "WAISTSLOT", [7] = "LEGSSLOT",
    [8] = "FEETSLOT", [9] = "WRISTSLOT", [10] = "HANDSSLOT", [16] = "MAINHANDSLOT",
    [17] = "SECONDARYHANDSLOT", [18] = "RANGEDSLOT",
}

TIP.dur = function(t)
    title(t, L.INFO_DUR_NAME)
    local any
    for slot = 1, 18 do
        local cur, max = call(GetInventoryItemDurability, slot)
        if type(cur) == "number" and type(max) == "number" and max > 0 then
            any = true
            local name = call(GetInventoryItemLink, "player", slot)
            if type(name) ~= "string" then
                local g = SLOTNAMES[slot] and _G[SLOTNAMES[slot]]
                name = type(g) == "string" and g or ("#" .. slot)
            end
            local p = cur / max * 100
            pair(t, name, string.format("%s%d%%|r %s", color(p), math.floor(p + 0.5), grey(cur .. "/" .. max)))
        end
    end
    if not any then t:AddLine(L.INFO_TIP_NODUR, 1, 1, 1) end
end

TIP.time = function(t)
    title(t, L.INFO_TIME_NAME)
    t:AddLine(date("%d/%m/%Y"), 1, 1, 1)
    pair(t, L.INFO_TIP_LOCAL, date("%H:%M:%S"))
    local h, m = call(GetGameTime)
    if type(h) == "number" and type(m) == "number" then
        pair(t, L.INFO_TIP_REALM, string.format("%02d:%02d", h, m))
    end
end

-- memoire des addons : mise a jour seulement a l entree du survol, hors combat
local function memory(t, update)
    local usage = GetAddOnMemoryUsage
    local num = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if type(usage) ~= "function" or type(num) ~= "function" or type(info) ~= "function" then return end
    if update and UpdateAddOnMemoryUsage and not InCombatLockdown() then pcall(UpdateAddOnMemoryUsage) end
    local list, total = {}, 0
    for i = 1, (call(num) or 0) do
        local kb = call(usage, i)
        if type(kb) == "number" and kb > 0 then
            local name, ttl = call(info, i)
            total = total + kb
            table.insert(list, { name = (type(ttl) == "string" and ttl ~= "" and ttl) or name or ("#" .. i), kb = kb })
        end
    end
    if #list == 0 then return end
    local function size(kb)
        if kb >= 1024 then return string.format(L.INFO_TIP_MB, kb / 1024) end
        return string.format(L.INFO_TIP_KB, kb)
    end
    table.sort(list, function(a, b) return a.kb > b.kb end)
    t:AddLine(" ")
    title(t, L.INFO_TIP_MEMORY)
    for i = 1, math.min(10, #list) do pair(t, list[i].name, size(list[i].kb)) end
    pair(t, L.INFO_TIP_TOTAL, size(total))
end

local function netTip(t, refreshing)
    title(t, L.INFO_FPS_NAME .. " / " .. L.INFO_LAT_NAME)
    local fps = call(GetFramerate)
    if type(fps) == "number" then pair(t, L.INFO_FPS_NAME, math.floor(fps + 0.5)) end
    local bIn, bOut, home, world = call(GetNetStats)
    if type(home) == "number" then pair(t, L.INFO_TIP_HOME, home .. " ms") end
    if type(world) == "number" then pair(t, L.INFO_TIP_WORLD, world .. " ms") end
    if type(bIn) == "number" then pair(t, L.INFO_TIP_IN, string.format(L.INFO_TIP_KBS, bIn)) end
    if type(bOut) == "number" then pair(t, L.INFO_TIP_OUT, string.format(L.INFO_TIP_KBS, bOut)) end
    memory(t, not refreshing)
end
TIP.fps = netTip
TIP.lat = netTip

TIP.coords = function(t)
    local zone = call(GetRealZoneText) or call(GetZoneText)
    title(t, (type(zone) == "string" and zone ~= "" and zone) or L.INFO_COORDS_NAME)
    local sub = call(GetSubZoneText)
    if type(sub) == "string" and sub ~= "" and sub ~= zone then t:AddLine(sub, 1, 1, 1) end
    local ok, txt = pcall(VALUE.coords)
    if ok and txt then pair(t, L.INFO_COORDS_NAME, txt) end
end

-- ligne "nom (niveau)" a gauche, zone a droite ; rien au-dela du maximum
local function member(t, n, name, level, zone)
    if n > MAXLINES then return end
    local left = name
    if type(level) == "number" and level > 0 then left = left .. grey(" (" .. level .. ")") end
    t:AddDoubleLine(left, type(zone) == "string" and zone or "", 1, 1, 1, C.text[1], C.text[2], C.text[3])
end

TIP.friends = function(t)
    title(t, L.INFO_FRIENDS_NAME)
    local n = 0
    local CF = C_FriendList
    if CF then
        for i = 1, (call(CF.GetNumFriends) or 0) do
            local info = call(CF.GetFriendInfoByIndex, i)
            if type(info) == "table" and clean(info.connected) then
                local name = clean(info.name)
                if type(name) == "string" then
                    n = n + 1
                    member(t, n, name, clean(info.level), clean(info.area))
                end
            end
        end
    end
    -- amis Battle.net connectes
    local BN = C_BattleNet
    local total = call(BNGetNumFriends)
    if BN and type(total) == "number" then
        local first = true
        for i = 1, total do
            local acc = call(BN.GetFriendAccountInfo, i)
            local g = type(acc) == "table" and clean(acc.gameAccountInfo)
            if type(g) == "table" and clean(g.isOnline) then
                if first and n < MAXLINES then t:AddLine(L.INFO_TIP_BNET, TITLE[1], TITLE[2], TITLE[3]) end
                first = false
                local name = clean(acc.accountName) or "?"
                local char = clean(g.characterName)
                if type(char) == "string" and char ~= "" then name = name .. grey(" - ") .. char end
                n = n + 1
                member(t, n, name, clean(g.characterLevel), clean(g.areaName) or clean(g.richPresence))
            end
        end
    end
    if n == 0 then t:AddLine(L.INFO_TIP_NONE, 1, 1, 1) end
    if n > MAXLINES then t:AddLine(string.format(L.INFO_TIP_MORE, n - MAXLINES), C.text[1], C.text[2], C.text[3]) end
end

local lastRoster = 0
TIP.guild = function(t, refreshing)
    if not call(IsInGuild) then
        title(t, L.INFO_GUILD_NAME)
        t:AddLine(L.INFO_TIP_NOGUILD, 1, 1, 1)
        return
    end
    -- liste a jour : demande au serveur, au plus toutes les 20 s
    if not refreshing and GetTime() - lastRoster > 20 then
        lastRoster = GetTime()
        call((C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster)
    end
    local gname = call(GetGuildInfo, "player")
    title(t, type(gname) == "string" and gname or L.INFO_GUILD_NAME)
    local n = 0
    for i = 1, (call(GetNumGuildMembers) or 0) do
        local name, _, _, level, _, zone, _, _, online, _, class = call(GetGuildRosterInfo, i)
        if online and type(name) == "string" then
            n = n + 1
            member(t, n, classHex(class) .. (name:match("^[^-]+") or name) .. "|r", level, zone)
        end
    end
    if n == 0 then t:AddLine(L.INFO_TIP_NONE, 1, 1, 1) end
    if n > MAXLINES then t:AddLine(string.format(L.INFO_TIP_MORE, n - MAXLINES), C.text[1], C.text[2], C.text[3]) end
end

---------------------------------------------------------------------------
-- Zones cliquables (boutons securises)
---------------------------------------------------------------------------

-- bouton de Blizzard (ou de CorpUI) a "cliquer", s il existe
local function btn(name)
    local f = _G[name]
    if type(f) == "table" and type(f.Click) == "function" then return f end
end
local function zoneButton()
    local ok, z = pcall(function() return MinimapCluster and MinimapCluster.ZoneTextButton end)
    if ok and type(z) == "table" and type(z.Click) == "function" then return z end
end

-- cible clic gauche, cible clic droit, et leurs aides
local TARGETS = {
    bags = function()
        return btn("CorpUIBagsToggle") or btn("MainMenuBarBackpackButton"), nil, "INFO_CLICK_BAGS"
    end,
    dur = function() return btn("CharacterMicroButton"), nil, "INFO_CLICK_CHAR" end,
    time = function()
        -- calendrier (bouton de la minicarte) ; horloge / chronometre (TimeManager, charge a la demande)
        return btn("GameTimeFrame"), btn("TimeManagerClockButton"), "INFO_CLICK_CALENDAR", "INFO_CLICK_CLOCK"
    end,
    coords = function()
        -- nom de zone de la minicarte (ouvre la carte du monde), sinon le journal de quetes
        return zoneButton() or btn("QuestLogMicroButton"), nil, "INFO_CLICK_MAP"
    end,
    friends = function()
        return btn("QuickJoinToastButton") or btn("FriendsMicroButton") or btn("SocialsMicroButton"), nil, "INFO_CLICK_FRIENDS"
    end,
    guild = function() return btn("GuildMicroButton"), nil, "INFO_CLICK_GUILD" end,
}

local tipOwner

local function showTip(b, refreshing)
    local key = b.cuiKey
    local t = ns.Tooltip(b, "ANCHOR_NONE")
    t:ClearAllPoints()
    -- au-dessus ou en dessous de la barre selon sa place a l ecran
    local _, cy = bar:GetCenter()
    local h = UIParent:GetHeight() / (bar:GetScale() or 1)
    if cy and h and cy > h / 2 then
        t:SetPoint("TOP", b, "BOTTOM", 0, -4)
    else
        t:SetPoint("BOTTOM", b, "TOP", 0, 4)
    end
    if db.tooltips and TIP[key] then
        local ok = pcall(TIP[key], t, refreshing)
        if not ok then t:AddLine("?") end
    else
        title(t, L["INFO_" .. strupper(key) .. "_NAME"])
    end
    if db.clicks and (b.cuiHint1 or b.cuiHint2) then
        t:AddLine(" ")
        if b.cuiHint1 then t:AddLine(L[b.cuiHint1], 0.5, 0.8, 1) end
        if b.cuiHint2 then t:AddLine(L[b.cuiHint2], 0.5, 0.8, 1) end
    end
    t:Show()
    tipOwner = b
end

local function makeHot(key)
    local b = CreateFrame("Button", "CorpUIInfoClick" .. key, UIParent, "SecureActionButtonTemplate")
    b.cuiKey = key
    -- appui ET relachement : l action securisee part sur l un ou l autre
    -- selon le reglage "action a l appui" (comme les boutons du micro-menu)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:Hide()
    b:SetScript("OnEnter", function(self) showTip(self) end)
    b:SetScript("OnLeave", function() tipOwner = nil ns.HideTooltip() end)
    hot[key] = b
    return b
end

-- attributs du clic : hors combat seulement
local function setTargets(b)
    local t1, t2, h1, h2
    if db.clicks and TARGETS[b.cuiKey] then t1, t2, h1, h2 = TARGETS[b.cuiKey]() end
    if t1 ~= b.cuiT1 then
        b:SetAttribute("type1", t1 and "click" or nil)
        b:SetAttribute("clickbutton1", t1)
        b.cuiT1 = t1
    end
    if t2 ~= b.cuiT2 then
        b:SetAttribute("type2", t2 and "click" or nil)
        b:SetAttribute("clickbutton2", t2)
        b.cuiT2 = t2
    end
    b.cuiHint1 = t1 and h1 or nil
    b.cuiHint2 = t2 and h2 or nil
end

local hotPending

-- place les zones sur les textes ; en combat, attend la fin du combat
local function syncHot()
    if not bar then return end
    if InCombatLockdown() then hotPending = true return end
    hotPending = false
    local active = bar:IsShown() and (db.clicks or db.tooltips)
    local left, bottom = bar:GetLeft(), bar:GetBottom()
    if not left or not bottom then active = false end
    local scale = bar:GetScale() or 1
    local strata, level = bar:GetFrameStrata() or "MEDIUM", (bar:GetFrameLevel() or 1) + 5
    for _, key in ipairs(ITEMS) do
        local b = hot[key] or makeHot(key)
        local p = active and db.items[key] and spots[key]
        if p then
            -- meme echelle que la barre : coordonnees dans le repere de la barre
            local x = math.floor(left + p.x + 0.5)
            local sig = table.concat({ x, math.floor(bottom + 0.5), p.w, db.height, scale, strata, level }, ":")
            if b.cuiSig ~= sig then
                b.cuiSig = sig
                b:SetScale(scale)
                b:SetFrameStrata(strata)
                b:SetFrameLevel(level)
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, math.floor(bottom + 0.5))
                b:SetSize(math.max(8, p.w), db.height)
            end
            setTargets(b)
            if not b:IsShown() then b:Show() end
        elseif b:IsShown() then
            b:Hide()
            b.cuiSig = nil
        end
    end
end

---------------------------------------------------------------------------
-- Barre
---------------------------------------------------------------------------

local function separator(i)
    if not seps[i] then
        local t = bar:CreateTexture(nil, "ARTWORK")
        t:SetWidth(1)
        ns.UI.Gradient(t, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0, C.violet[1], C.violet[2], C.violet[3], 0.8)
        seps[i] = t
    end
    return seps[i]
end

local function refresh()
    if not bar then return end
    if not bar:IsShown() then syncHot() return end
    -- textes visibles, dans l ordre choisi
    local shown, keys, total = {}, {}, 0
    for k in pairs(spots) do spots[k] = nil end
    for _, key in ipairs(db.order) do
        local fs = texts[key]
        if db.items[key] then
            local ok, txt = pcall(VALUE[key])
            fs:SetText(ok and txt or "?")
            fs:Show()
            table.insert(shown, fs)
            table.insert(keys, key)
            total = total + fs:GetStringWidth()
        else
            fs:Hide()
        end
    end
    local n = #shown
    local gap = db.spacing
    local width
    local x = PAD
    if db.width > 0 then
        width = db.width
        local used = total + gap * math.max(0, n - 1)
        if db.align == "center" then
            x = math.max(PAD, (width - used) / 2)
        elseif db.align == "spread" and n > 1 then
            gap = math.max(4, (width - 2 * PAD - total) / (n - 1))
        end
    else
        width = math.max(60, total + gap * math.max(0, n - 1) + 2 * PAD)
    end
    bar:SetWidth(width)
    for i, fs in ipairs(shown) do
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", bar, "LEFT", math.floor(x + 0.5), 0)
        -- zone cliquable : le texte et la moitie des espaces qui l entourent
        local sw = fs:GetStringWidth()
        local zx = math.max(0, x - gap / 2)
        spots[keys[i]] = { x = zx, w = math.floor(x + sw + gap / 2 - zx + 0.5) }
        x = x + sw
        -- separateur au milieu de l espace qui suit
        local s = separator(i)
        if db.separators and i < n then
            s:ClearAllPoints()
            s:SetPoint("CENTER", bar, "LEFT", math.floor(x + gap / 2 + 0.5), 0)
            s:SetHeight(math.max(8, db.height - 8))
            s:Show()
        else
            s:Hide()
        end
        x = x + gap
    end
    for i = n + 1, #seps do seps[i]:Hide() end
    syncHot()
    -- infobulle ouverte : contenu a jour (sans remesurer la memoire)
    if tipOwner and tipOwner:IsShown() and tipOwner:IsMouseOver() then showTip(tipOwner, true) end
end

local function apply()
    bar:SetShown(db.enabled)
    bar:SetScale(db.scale)
    bar:SetHeight(db.height)
    local a = db.alpha / 100
    bar.cuiBg:SetAlpha(a)
    bar.cuiBg:SetShown(db.backdrop)
    bar.cuiBorder:SetShown(db.backdrop)
    for _, t in ipairs(bar.shadow) do t:SetShown(db.backdrop) end
    -- sans fond : contour pour rester lisible sur le decor
    local file = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    for _, fs in pairs(texts) do
        if not pcall(fs.SetFont, fs, file, db.fontSize, db.backdrop and "" or "OUTLINE") then
            fs:SetFontObject("GameFontHighlightSmall")
        end
    end
    if not db.mouseover then bar:SetAlpha(1) end
    refresh()
end

local function build()
    db.pos = db.pos or { point = "TOP", x = 0, y = -86 }
    -- premiere position par defaut, sous une barre d XP courante : trop haute
    if db.pos.point == "TOP" and db.pos.y == -64 and not db.pos.rel then db.pos.y = -86 end
    bar = CreateFrame("Frame", "CorpUIInfoBar", UIParent)
    bar:SetSize(300, db.height)
    ns.ApplyPos(bar, db.pos)
    -- fond, liseré et ombre (les textures d ombre sont gardees pour les masquer)
    local before = { bar:GetRegions() }
    ns.UI.Skin(bar, 1, true)
    bar.shadow = {}
    local known = {}
    for _, r in ipairs(before) do known[r] = true end
    for _, r in ipairs({ bar:GetRegions() }) do
        if not known[r] and r ~= bar.cuiBg and r ~= bar.cuiBorder then table.insert(bar.shadow, r) end
    end
    for _, key in ipairs(ITEMS) do
        texts[key] = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end
    ns.UI.Mover(bar, db.pos, L.MOD_INFO)
    local elapsed = 1
    bar:SetScript("OnUpdate", function(self, dt)
        -- fondu "au survol"
        if db.mouseover then
            local want = (self:IsMouseOver() or ns.moversShown) and 1 or 0
            local a = self:GetAlpha()
            if a ~= want then self:SetAlpha(want > a and math.min(1, a + dt * 5) or math.max(0, a - dt * 3)) end
        end
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        refresh()
    end)
    apply()
end

---------------------------------------------------------------------------
-- Fenetre d options
---------------------------------------------------------------------------

local win

local function buildWindow()
    win = ns.UI.Window("CorpUIInfoOptions", ns.TITLE .. " - " .. L.MOD_INFO, nil, 440, 680)
    local refreshers = {}
    local function redraw() for _, r in ipairs(refreshers) do r() end end
    local y = -34

    local function check(text, get, set, x)
        local c = ns.UI.Check(win, text, function(v) set(v) apply() redraw() end)
        c:SetPoint("TOPLEFT", x or 4, y)
        y = y - 24
        table.insert(refreshers, function() c:SetChecked(get()) end)
        return c
    end
    local function stepper(textFn, change)
        local fs = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 8, y - 5)
        local function go(d)
            change(d * (IsShiftKeyDown() and 5 or 1))
            apply()
            redraw()
        end
        local minus = ns.UI.Button(win, "-", 24, function() go(-1) end)
        minus:SetPoint("TOPLEFT", 230, y)
        local plus = ns.UI.Button(win, "+", 24, function() go(1) end)
        plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
        y = y - 26
        table.insert(refreshers, function() fs:SetText(textFn()) end)
    end
    local function num(key, fmt, lo, hi, step)
        stepper(function() return string.format(fmt, db[key]) end,
            function(d)
                local v = math.floor((db[key] + d * (step or 1)) * 100 + 0.5) / 100
                db[key] = math.max(lo, math.min(hi, v))
            end)
    end

    check(L.INFO_OPT_ENABLE, function() return db.enabled end, function(v) db.enabled = v end)

    -- infos affichees, avec fleches pour l ordre
    y = y - 6
    local head = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", 8, y)
    head:SetText(L.INFO_ITEMS)
    y = y - 20
    local rows = {}
    for i = 1, #ITEMS do
        local row = {}
        row.check = ns.UI.Check(win, "", function(v) db.items[db.order[i]] = v apply() redraw() end)
        row.check:SetPoint("TOPLEFT", 4, y)
        row.up = ns.UI.Button(win, "^", 22, function()
            if i > 1 then db.order[i], db.order[i - 1] = db.order[i - 1], db.order[i] end
            apply() redraw()
        end)
        row.up:SetSize(22, 20)
        row.up:SetPoint("TOPLEFT", 230, y - 1)
        row.down = ns.UI.Button(win, "v", 22, function()
            if i < #db.order then db.order[i], db.order[i + 1] = db.order[i + 1], db.order[i] end
            apply() redraw()
        end)
        row.down:SetSize(22, 20)
        row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
        rows[i] = row
        y = y - 22
    end
    table.insert(refreshers, function()
        for i, row in ipairs(rows) do
            local key = db.order[i]
            row.check.label:SetText(L["INFO_" .. strupper(key) .. "_NAME"])
            row.check:SetHitRectInsets(0, -(row.check.label:GetStringWidth() + 4), 0, 0)
            row.check:SetChecked(db.items[key])
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(i < #db.order)
        end
    end)

    -- apparence : formulaire commun (curseurs, listes, deux colonnes)
    local form = ns.UI.Form(win, y - 4, function() apply() redraw() end)
    form:Header(L.INFO_LAYOUT)
    form:Columns(2)
    local function fnum(fmt, key, lo, hi, step)
        form:Number(fmt, function() return db[key] end, function(v) db[key] = v end, lo, hi, step)
    end
    fnum(L.INFO_HEIGHT, "height", 14, 40)
    fnum(L.INFO_FONT, "fontSize", 8, 18)
    fnum(L.INFO_SPACING, "spacing", 4, 60)
    -- largeur : 0 = automatique
    form:Number(ns.UI.LabelOf(L.INFO_WIDTH) .. " (0 = " .. L.INFO_AUTO .. ")", function() return db.width end,
        function(v) db.width = v < 100 and 0 or v end, 0, 1600, 10)
    form:Cycle(L.INFO_ALIGN, ALIGNS, { left = L.INFO_ALIGN_LEFT, center = L.INFO_ALIGN_CENTER, spread = L.INFO_ALIGN_SPREAD },
        function() return db.align end, function(v) db.align = v end)
    fnum(L.FRAMES_SCALE, "scale", 0.6, 1.6, 0.1)
    fnum(L.INFO_ALPHA, "alpha", 10, 100, 5)
    form:Check(L.INFO_BACKDROP, function() return db.backdrop end, function(v) db.backdrop = v end)
    form:Check(L.INFO_SEPARATORS, function() return db.separators end, function(v) db.separators = v end)
    form:Check(L.INFO_MOUSEOVER, function() return db.mouseover end, function(v) db.mouseover = v end)
    form:EndColumns()
    -- clics et infobulles (les zones cliquables sont replacees hors combat)
    form:Header(L.INFO_INTERACT)
    form:Check(L.INFO_OPT_CLICKS, function() return db.clicks end, function(v) db.clicks = v end)
    form:Check(L.INFO_OPT_TIPS, function() return db.tooltips end, function(v) db.tooltips = v end)

    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.INFO_HINT)

    win:HookScript("OnShow", function() redraw() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_MONEY" then trackMoney() return end
    if event == "PLAYER_REGEN_ENABLED" then
        if hotPending and db then syncHot() end
        return
    end
    if event ~= "PLAYER_LOGIN" then return end
    local root = ns.InitRoot()
    root.info = root.info or {}
    db = root.info
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    db.items = db.items or {}
    for key, on in pairs(DEFAULT_ON) do if db.items[key] == nil then db.items[key] = on end end
    -- ordre : celui enregistre, puis les infos ajoutees depuis
    db.order = db.order or {}
    local seen = {}
    local order = {}
    for _, key in ipairs(db.order) do
        if VALUE[key] and not seen[key] then seen[key] = true table.insert(order, key) end
    end
    for _, key in ipairs(ITEMS) do if not seen[key] then table.insert(order, key) end end
    db.order = order
    trackMoney()
    build()
end)
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "PLAYER_MONEY")

-- liste de guilde : le serveur ne l envoie que sur demande (a la connexion,
-- puis toutes les 60 s ; le client limite lui-meme la frequence)
do
    local roster = CreateFrame("Frame")
    local wait = 3
    roster:SetScript("OnUpdate", function(_, dt)
        wait = wait - dt
        if wait > 0 then return end
        wait = 60
        if IsInGuild and IsInGuild() then
            local fn = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
            if fn then pcall(fn) end
        end
    end)
end
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ns.RegisterModule({
    command = "infos",
    panelName = "CorpUIInfoOptions",
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    title = function() return L.MOD_INFO end,
    desc = function() return L.INFO_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})
