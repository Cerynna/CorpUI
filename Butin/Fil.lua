--[[--------------------------------------------------------------------------
    CorpUI - fil du butin
    (idee vue dans NaowhForever, « tous droits reserves » : rien de leur
    code ; ecrit pour CorpUI)

    Une ligne par gain, qui s efface apres quelques secondes :
      - objet ramasse, recu ou fabrique (CHAT_MSG_LOOT, messages du jeu a
        soi : LOOT_ITEM_SELF / PUSHED / CREATED, simples et multiples) :
        icone, liseré et nom a la couleur de qualite, quantite, nombre dans
        les sacs, valeur (HV si le module tourne et connait l objet, sinon
        prix du marchand) ;
      - argent ramasse (CHAT_MSG_MONEY : GOLD / SILVER / COPPER_AMOUNT) ;
      - experience (PLAYER_XP_UPDATE : ecart de UnitXP, passage de niveau
        compris) ;
      - reputation (CHAT_MSG_COMBAT_FACTION_CHANGE : hausse seulement) ;
      - quete rendue (QUEST_TURNED_IN : titre, argent).
    Un meme gain encore affiche se cumule sur sa ligne (quantite, argent,
    experience) au lieu d en ajouter une. Pied en option : butin de la
    session (argent + valeur des objets) et or par heure.
    Textes secrets (verrou de discussion) : ignores, jamais compares.
    Deverrouillage : apercu fixe, deplacable par sa poignee.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local DEFAULTS = {
    items = true, minQuality = 0, crafted = true, money = true, xp = true, rep = true, quests = true,
    duration = 6, max = 6, width = 240, height = 24, bgAlpha = 70, grow = "up", value = "auto", gph = true,
}

local APPEAR, FADE, SLIDE = 0.15, 0.4, 14
local GAP = 2
local ICON_MONEY = "Interface\\Icons\\INV_Misc_Coin_01"
local ICON_XP = "Interface\\Icons\\INV_Misc_Book_09"
local ICON_REP = "Interface\\Icons\\INV_Scroll_03"
local ICON_QUEST = "Interface\\GossipFrame\\ActiveQuestIcon"
local XP_RGB = { 0.72, 0.56, 1 }
local REP_RGB = { 0.35, 0.78, 1 }
local QUEST_RGB = { 1, 0.82, 0.25 }

local db
local holder, footer
local rows = {}             -- lignes affichees, de la plus ancienne a la plus recente
local pool = {}
local previewOn = false
local session = { start = nil, value = 0 }
local xpLast = {}

---------------------------------------------------------------------------
-- Lectures prudentes
---------------------------------------------------------------------------

local function str(v)
    if issecret(v) or type(v) ~= "string" then return nil end
    return v
end

local function num(v)
    if issecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- motif Lua d un texte du jeu ("Vous recevez le butin : %sx%d.") : %s et
-- %d deviennent des captures, positions ("%1$s") comprises
local function patternOf(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = fmt:gsub("%%%d%$", "%%")
    p = p:gsub("([%(%)%.%[%]%^%$%*%+%-%?])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

-- objets : les messages multiples avant les simples (le simple avalerait "x3")
local ITEM_FORMATS = {
    { "LOOT_ITEM_SELF_MULTIPLE" }, { "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }, { "LOOT_ITEM_CREATED_SELF_MULTIPLE", crafted = true },
    { "LOOT_ITEM_SELF" }, { "LOOT_ITEM_PUSHED_SELF" }, { "LOOT_ITEM_CREATED_SELF", crafted = true },
}
local itemPatterns, repPatterns, coinPatterns

local function buildPatterns()
    itemPatterns, repPatterns = {}, {}
    for _, f in ipairs(ITEM_FORMATS) do
        local p = patternOf(_G[f[1]])
        if p then table.insert(itemPatterns, { p = p, crafted = f.crafted }) end
    end
    for _, g in ipairs({ "FACTION_STANDING_INCREASED", "FACTION_STANDING_INCREASED_GENERIC" }) do
        local p = patternOf(_G[g])
        if p then table.insert(repPatterns, p) end
    end
    coinPatterns = {}
    for i, g in ipairs({ "GOLD_AMOUNT", "SILVER_AMOUNT", "COPPER_AMOUNT" }) do
        local fmt = _G[g]
        if type(fmt) == "string" then
            coinPatterns[i] = fmt:gsub("([%(%)%.%[%]%^%$%*%+%-%?])", "%%%1"):gsub("%%d", "(%%d+)")
        end
    end
end

-- captures d un message : le lien d objet et le premier nombre, dans
-- n importe quel ordre (langues ou l ordre des %s / %d change)
local function linkAndCount(...)
    local link, count
    for i = 1, select("#", ...) do
        local c = select(i, ...)
        if type(c) == "string" then
            if not link and c:find("|H", 1, true) then link = c
            elseif not count and c:match("^%d+$") then count = tonumber(c) end
        end
    end
    return link, count
end

local function itemInfo(link)
    local id = tonumber(link:match("item:(%d+)"))
    local name = link:match("|h%[(.-)%]|h") or link
    local color = link:match("|c(%x%x%x%x%x%x%x%x)")
    local icon, quality, sell
    if id then
        local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if fn then
            local ok, _, _, _, _, tex = pcall(fn, id)
            if ok then icon = tex end
        end
        local fi = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if fi then
            local ok, _, _, q, _, _, _, _, _, _, tex, price = pcall(fi, link)
            if ok then
                quality = num(q)
                sell = num(price)
                icon = icon or tex
            end
        end
        if not quality and C_Item and C_Item.GetItemQualityByID then
            local ok, q = pcall(C_Item.GetItemQualityByID, id)
            if ok then quality = num(q) end
        end
    end
    return id, name, color, icon or "Interface\\Icons\\INV_Misc_QuestionMark", quality, sell
end

-- valeur d un exemplaire selon le reglage (HV, marchand, auto, aucune)
local function unitValue(id, sell)
    local mode = db.value
    if mode == "none" then return nil end
    if mode ~= "vendor" and id and ns.AHValues and ns.ModuleOn("hv") then
        local ok, v = pcall(ns.AHValues, id)
        if ok and type(v) == "table" and num(v.market) and v.market > 0 then return v.market end
        if mode == "ah" then return nil end
    end
    if sell and sell > 0 then return sell end
end

local function bagCount(id)
    if not id then return nil end
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn then return nil end
    local ok, n = pcall(fn, id)
    return ok and num(n) or nil
end

-- "12po 34pa" : les deux plus grosses pieces seulement
local function shortMoney(copper)
    copper = math.floor((copper or 0) + 0.5)
    local G, S, Cu = ns.MoneySymbols()
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return s > 0 and (g .. G .. " " .. s .. S) or (g .. G) end
    if s > 0 then return c > 0 and (s .. S .. " " .. c .. Cu) or (s .. S) end
    return c .. Cu
end

local function bigNumber(n)
    if BreakUpLargeNumbers then
        local ok, t = pcall(BreakUpLargeNumbers, n)
        if ok and type(t) == "string" then return t end
    end
    return tostring(n)
end

---------------------------------------------------------------------------
-- Lignes
---------------------------------------------------------------------------

local function font(fs, size)
    local file = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    pcall(fs.SetFont, fs, file, size, "OUTLINE")
    fs:SetShadowColor(0, 0, 0, 0)
end

local function newRow()
    local r = CreateFrame("Frame", nil, holder)
    ns.UI.Skin(r, 0.7)
    r.bar = r:CreateTexture(nil, "ARTWORK", nil, 2)
    r.bar:SetPoint("TOPLEFT", 0, 0)
    r.bar:SetPoint("BOTTOMLEFT", 0, 0)
    r.bar:SetWidth(2)
    ns.NoSnap(r.bar)
    r.iconEdge = r:CreateTexture(nil, "ARTWORK")
    r.iconEdge:SetColorTexture(0, 0, 0, 1)
    r.icon = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.icon:SetPoint("TOPLEFT", r.iconEdge, "TOPLEFT", 1, -1)
    r.icon:SetPoint("BOTTOMRIGHT", r.iconEdge, "BOTTOMRIGHT", -1, 1)
    r.bags = r:CreateFontString(nil, "OVERLAY")
    r.bags:SetPoint("BOTTOMRIGHT", r.iconEdge, "BOTTOMRIGHT", 1, 0)
    r.value = r:CreateFontString(nil, "OVERLAY")
    r.value:SetJustifyH("RIGHT")
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:Hide()
    return r
end

-- taille et polices d une ligne selon les reglages
local function shape(r)
    local h = db.height
    r:SetSize(db.width, h)
    r.cuiBg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], db.bgAlpha / 100)
    r.cuiBorder:SetColorTexture(0, 0, 0, math.min(1, db.bgAlpha / 100 + 0.2))
    r.iconEdge:ClearAllPoints()
    r.iconEdge:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.iconEdge:SetSize(h - 4, h - 4)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local size = math.max(9, math.floor(h * 0.5 + 0.5))
    font(r.name, size)
    font(r.value, size - 1)
    font(r.bags, math.max(8, size - 3))
    r.value:ClearAllPoints()
    r.value:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", r.iconEdge, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
end

-- textes d une ligne d apres ses donnees
local function fill(r)
    local e = r.entry
    local cr, cg, cb = 1, 1, 1
    if e.rgb then cr, cg, cb = e.rgb[1], e.rgb[2], e.rgb[3] end
    r.bar:SetColorTexture(cr, cg, cb, 1)
    r.icon:SetTexture(e.icon)
    local text = e.text
    if e.kind == "item" then
        text = (e.color and ("|c" .. e.color) or "") .. e.text .. "|r"
        if e.count > 1 then text = text .. " |cff7fe07fx" .. e.count .. "|r" end
    end
    r.name:SetText(text)
    if e.kind ~= "item" then r.name:SetTextColor(cr, cg, cb) else r.name:SetTextColor(1, 1, 1) end
    local v = e.value
    r.value:SetText(v and v > 0 and shortMoney(v) or "")
    r.bags:SetText(e.bags and e.bags > 1 and tostring(e.bags) or "")
end

-- disposition : la plus recente au bord de depart, les autres s en eloignent
local function layout()
    local up = db.grow ~= "down"
    local n = #rows
    for i, row in ipairs(rows) do
        local k = n - i              -- 0 = la plus recente
        local f = row.frame
        f:ClearAllPoints()
        local y = k * (db.height + GAP)
        local dx = row.slide or 0
        if up then
            f:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", dx, y)
        else
            f:SetPoint("TOPLEFT", holder, "TOPLEFT", dx, -y)
        end
    end
    -- pied : du cote oppose au depart
    footer:ClearAllPoints()
    if up then
        footer:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 2, -3)
    else
        footer:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 2, 3)
    end
end

local function release(row)
    row.frame:Hide()
    row.frame.entry = nil
    table.insert(pool, row.frame)
end

local function sessionText()
    if not session.start or session.value <= 0 then return "" end
    local secs = math.max(60, GetTime() - session.start)
    return string.format(L.FEED_SESSION, shortMoney(session.value), shortMoney(session.value * 3600 / secs))
end

local function updateFooter()
    if not footer then return end
    local t = db.gph and (previewOn and string.format(L.FEED_SESSION, shortMoney(156040), shortMoney(412550)) or sessionText()) or ""
    footer:SetText(t)
    footer:SetShown(t ~= "")
end

local ticker

local function startTicker()
    if ticker then return end
    ticker = true
    holder:SetScript("OnUpdate", function(_, dt)
        local now = GetTime()
        local changed, busy = false, false
        for i = #rows, 1, -1 do
            local row = rows[i]
            local f = row.frame
            local age = now - row.born
            local a = 1
            if age < APPEAR or not row.keep then busy = true end
            if age < APPEAR then
                a = age / APPEAR
                row.slide = SLIDE * (1 - a)
                changed = true
            elseif row.slide and row.slide ~= 0 then
                row.slide = 0
                changed = true
            end
            if not row.keep then
                local left = row.until_ - now
                if left <= 0 then
                    release(row)
                    table.remove(rows, i)
                    changed = true
                    a = nil
                elseif left < FADE then
                    a = math.min(a, left / FADE)
                end
            end
            if a then f:SetAlpha(a) end
        end
        if changed then layout() end
        -- plus rien a animer (lignes d apercu posees) : on s arrete
        if not busy then
            holder:SetScript("OnUpdate", nil)
            ticker = nil
        end
    end)
end

-- ajoute un gain ; un gain de meme cle encore affiche est cumule
local function push(entry)
    if not holder then return end
    local now = GetTime()
    for _, row in ipairs(rows) do
        if row.key == entry.key and not row.keep and row.until_ - now > FADE then
            local e = row.frame.entry
            e.count = (e.count or 0) + (entry.count or 0)
            if entry.value then e.value = (e.value or 0) + entry.value end
            if entry.amount then
                e.amount = (e.amount or 0) + entry.amount
                e.text = entry.textOf(e.amount)
            end
            e.bags = entry.bags or e.bags
            row.until_ = now + db.duration
            fill(row.frame)
            row.frame:SetAlpha(1)
            return
        end
    end
    -- trop de lignes : la plus ancienne s en va
    while #rows >= db.max do
        release(rows[1])
        table.remove(rows, 1)
    end
    local f = table.remove(pool) or newRow()
    shape(f)
    f.entry = entry
    fill(f)
    f:SetAlpha(0)
    f:Show()
    table.insert(rows, { frame = f, key = entry.key, born = now, until_ = now + db.duration, slide = SLIDE, keep = entry.keep })
    layout()
    startTicker()
end

local function addValue(v)
    if not v or v <= 0 then return end
    session.start = session.start or GetTime()
    session.value = session.value + v
    updateFooter()
end

---------------------------------------------------------------------------
-- Gains
---------------------------------------------------------------------------

local function onLoot(msg)
    msg = str(msg)
    if not msg or not db.items then return end
    for _, ip in ipairs(itemPatterns) do
        local link, count = linkAndCount(msg:match(ip.p))
        if link then
            if ip.crafted and not db.crafted then return end
            local id, name, color, icon, quality, sell = itemInfo(link)
            if quality and quality < db.minQuality then return end
            count = count or 1
            local unit = unitValue(id, sell)
            local value = unit and unit * count or nil
            local r, g, b = 1, 1, 1
            if color then
                r = tonumber(color:sub(3, 4), 16) / 255
                g = tonumber(color:sub(5, 6), 16) / 255
                b = tonumber(color:sub(7, 8), 16) / 255
            end
            push({ kind = "item", key = "item:" .. (id or name), text = name, color = color, rgb = { r, g, b },
                   icon = icon, count = count, value = value, bags = bagCount(id), id = id })
            addValue(value)
            return
        end
    end
end

local function onMoney(msg)
    msg = str(msg)
    if not msg or not db.money then return end
    local total, found = 0, false
    for i, p in ipairs(coinPatterns) do
        local n = tonumber(msg:match(p))
        if n then
            found = true
            total = total + n * (i == 1 and 10000 or i == 2 and 100 or 1)
        end
    end
    if not found or total <= 0 then return end
    push({ kind = "money", key = "money", text = L.FEED_MONEY_ROW, rgb = QUEST_RGB, icon = ICON_MONEY, count = 0, value = total })
    addValue(total)
end

local function xpText(n) return string.format(L.FEED_XP_FMT, bigNumber(n)) end

local function readXP()
    local x, m, lv = num(UnitXP("player")), num(UnitXPMax("player")), num(UnitLevel("player"))
    return x, m, lv
end

local function onXP()
    local x, m, lv = readXP()
    if not x or not m or not lv then return end
    local d
    if xpLast.x then
        if lv > xpLast.lv then
            d = (xpLast.m - xpLast.x) + x
        else
            d = x - xpLast.x
        end
    end
    xpLast.x, xpLast.m, xpLast.lv = x, m, lv
    if not d or d <= 0 or not db.xp then return end
    push({ kind = "xp", key = "xp", text = xpText(d), amount = d, textOf = xpText, rgb = XP_RGB, icon = ICON_XP, count = 0 })
end

local function onFaction(msg)
    msg = str(msg)
    if not msg or not db.rep then return end
    for _, p in ipairs(repPatterns) do
        local a, b = msg:match(p)
        if a then
            local faction, amount = a, tonumber(b)
            if not amount then faction, amount = b, tonumber(a) end
            if faction and amount and amount > 0 then
                local textOf = function(n) return string.format(L.FEED_REP_FMT, bigNumber(n), faction) end
                push({ kind = "rep", key = "rep:" .. faction, text = textOf(amount), amount = amount, textOf = textOf,
                       rgb = REP_RGB, icon = ICON_REP, count = 0 })
            end
            return
        end
    end
end

local function questTitle(id)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok and str(t) and t ~= "" then return t end
    end
    return L.FEED_QUEST_DONE
end

local function onQuest(questID, _, money)
    if not db.quests then return end
    local id = num(questID)
    local m = num(money)
    push({ kind = "quest", key = "quest:" .. tostring(id), text = id and questTitle(id) or L.FEED_QUEST_DONE,
           rgb = QUEST_RGB, icon = ICON_QUEST, count = 0, value = m and m > 0 and m or nil })
    if m then addValue(m) end
end

-- nombre dans les sacs : les sacs sont a jour apres le message du butin
local function refreshBags()
    for _, row in ipairs(rows) do
        local e = row.frame.entry
        if e and e.kind == "item" and e.id and not row.keep then
            e.bags = bagCount(e.id)
            fill(row.frame)
        end
    end
end

---------------------------------------------------------------------------
-- Apercu (deverrouillage, bouton des options)
---------------------------------------------------------------------------

local function clearRows()
    for _, row in ipairs(rows) do release(row) end
    wipe(rows)
end

local function sampleItem(id, quality, count, bags, value)
    local name = ns.ItemName(id) or ("item:" .. id)
    local color = ({ [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee" })[quality]
    local icon
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if fn then
        local ok, _, _, _, _, tex = pcall(fn, id)
        if ok then icon = tex end
    end
    local r = tonumber(color:sub(3, 4), 16) / 255
    local g = tonumber(color:sub(5, 6), 16) / 255
    local b = tonumber(color:sub(7, 8), 16) / 255
    return { kind = "item", key = "preview:" .. id, text = name, color = color, rgb = { r, g, b },
             icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark", count = count, value = value, bags = bags, keep = true }
end

local function showPreview(on)
    previewOn = on and true or false
    clearRows()
    if previewOn then
        -- du plus ancien au plus recent
        push({ kind = "quest", key = "preview:quest", text = L.FEED_QUEST_DONE, rgb = QUEST_RGB, icon = ICON_QUEST,
               count = 0, value = 4500, keep = true })
        push({ kind = "rep", key = "preview:rep", text = string.format(L.FEED_REP_FMT, "250", FACTION or "Faction"),
               rgb = REP_RGB, icon = ICON_REP, count = 0, keep = true })
        push({ kind = "xp", key = "preview:xp", text = xpText(1240), rgb = XP_RGB, icon = ICON_XP, count = 0, keep = true })
        push({ kind = "money", key = "preview:money", text = L.FEED_MONEY_ROW, rgb = QUEST_RGB, icon = ICON_MONEY, count = 0,
               value = 31250, keep = true })
        push(sampleItem(2589, 1, 3, 17, 30))
        push(sampleItem(6268, 2, 1, 1, 1840))
    end
    updateFooter()
end

---------------------------------------------------------------------------
-- Cadre, reglages
---------------------------------------------------------------------------

local function sizeHolder()
    holder:SetSize(db.width, db.max * (db.height + GAP) - GAP)
end

local function apply()
    if not holder then return end
    sizeHolder()
    for _, row in ipairs(rows) do shape(row.frame) fill(row.frame) end
    for _, f in ipairs(pool) do shape(f) end
    layout()
    -- apercu du deverrouillage : tant que les poignees sont montrees
    local want = ns.moversShown and true or false
    if want ~= previewOn and not (previewOn and holder.manualPreview) then showPreview(want) end
    updateFooter()
end

local function build()
    holder = CreateFrame("Frame", "CorpUILootFeed", UIParent)
    holder:SetFrameStrata("MEDIUM")
    ns.ApplyPos(holder, db.pos)
    footer = holder:CreateFontString(nil, "OVERLAY")
    holder.footer = footer
    font(footer, 11)
    footer:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    sizeHolder()
    holder.mover = ns.UI.Mover(holder, db.pos, L.MOD_FEED)
    layout()
end

local win

local function buildOptions()
    win = ns.UI.Window("CorpUILootFeedOptions", ns.TITLE .. " - " .. L.MOD_FEED, nil, 440, 300)
    local form = ns.UI.Form(win, -34, function() apply() end)
    form:Header(L.FEED_H_SHOW)
    form:Columns(2)
    for _, k in ipairs({ { "items", L.FEED_ITEMS }, { "crafted", L.FEED_CRAFTED }, { "money", L.FEED_MONEY },
                         { "xp", L.FEED_XP }, { "rep", L.FEED_REP }, { "quests", L.FEED_QUESTS } }) do
        form:Switch(k[2], function() return db[k[1]] end, function(v) db[k[1]] = v end)
    end
    form:EndColumns()
    local qualities, qnames = {}, {}
    for q = 0, 4 do
        table.insert(qualities, q)
        qnames[q] = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
    end
    form:Columns(2)
    form:Cycle(L.FEED_MINQ, qualities, qnames, function() return db.minQuality end, function(v) db.minQuality = v end)
    form:Cycle(L.FEED_VALUE, { "auto", "ah", "vendor", "none" },
        { auto = L.FEED_VALUE_AUTO, ah = L.FEED_VALUE_AH, vendor = L.FEED_VALUE_VENDOR, none = L.FEED_VALUE_NONE },
        function() return db.value end, function(v) db.value = v end)
    form:EndColumns()
    form:Header(L.FEED_H_LOOK)
    form:Columns(2)
    form:Number(L.FEED_DURATION, function() return db.duration end, function(v) db.duration = v end, 2, 15)
    form:Number(L.FEED_MAX, function() return db.max end, function(v) db.max = v end, 3, 10)
    form:Number(L.FEED_WIDTH, function() return db.width end, function(v) db.width = v end, 160, 400, 10)
    form:Number(L.FEED_HEIGHT, function() return db.height end, function(v) db.height = v end, 18, 36)
    form:Number(L.FEED_BG, function() return db.bgAlpha end, function(v) db.bgAlpha = v end, 0, 100, 5)
    form:Cycle(L.FEED_GROW, { "up", "down" }, { up = L.FEED_GROW_UP, down = L.FEED_GROW_DOWN },
        function() return db.grow end, function(v) db.grow = v end)
    form:EndColumns()
    form:Switch(L.FEED_GPH, function() return db.gph end, function(v) db.gph = v end)
    form:Gap(4)
    local prev = ns.UI.Button(win, L.FEED_PREVIEW, 130, function()
        holder.manualPreview = not previewOn
        showPreview(not previewOn)
    end)
    prev:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y)
    local reset = ns.UI.Button(win, L.FEED_RESET, 150, function()
        session.start, session.value = nil, 0
        updateFooter()
    end)
    reset:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    form:Gap(30)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 4)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.FEED_HINT)
    win:SetHeight(math.floor(80 - form.y))
    win:HookScript("OnShow", function() form:Refresh() end)
    win:HookScript("OnHide", function()
        if holder.manualPreview then
            holder.manualPreview = nil
            apply()
        end
    end)
end

local function toggle()
    if not db then return end
    if not win then buildOptions() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
    if ns.ModuleOff("fil", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.lootfeed) ~= "table" then root.lootfeed = {} end
        db = root.lootfeed
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        if type(db.pos) ~= "table" then db.pos = { point = "CENTER", x = 360, y = -60 } end
        buildPatterns()
        build()
        xpLast.x, xpLast.m, xpLast.lv = readXP()
        apply()
        return
    end
    if not db or not holder or previewOn then
        if event == "PLAYER_XP_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            xpLast.x, xpLast.m, xpLast.lv = readXP()
        end
        return
    end
    if event == "CHAT_MSG_LOOT" then
        onLoot((...))
    elseif event == "CHAT_MSG_MONEY" then
        onMoney((...))
    elseif event == "PLAYER_XP_UPDATE" then
        local unit = ...
        if unit == nil or unit == "player" then onXP() end
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        onFaction((...))
    elseif event == "QUEST_TURNED_IN" then
        onQuest(...)
    elseif event == "BAG_UPDATE_DELAYED" then
        refreshBags()
    elseif event == "PLAYER_ENTERING_WORLD" then
        xpLast.x, xpLast.m, xpLast.lv = readXP()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "PLAYER_XP_UPDATE",
                     "CHAT_MSG_COMBAT_FACTION_CHANGE", "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED",
                     "PLAYER_ENTERING_WORLD" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.Listen(function() if db and holder then apply() end end)

ns.RegisterModule({
    command = "fil",
    alias = "lootfeed",
    panelName = "CorpUILootFeedOptions",
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
    title = function() return L.MOD_FEED end,
    desc = function() return L.FEED_DESC end,
    Slash = function(input)
        local cmd = strlower(strtrim(input or ""))
        if cmd == "reset" or cmd == "zero" then
            session.start, session.value = nil, 0
            updateFooter()
            return
        end
        if cmd == "test" or cmd == "apercu" then
            if holder then
                holder.manualPreview = not previewOn
                showPreview(not previewOn)
            end
            return
        end
        toggle()
    end,
    Open = toggle,
})
