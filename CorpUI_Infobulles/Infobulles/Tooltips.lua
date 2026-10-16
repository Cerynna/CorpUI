--[[--------------------------------------------------------------------------
    CorpUI - module Infobulles
    Style CorpUI pour les infobulles du jeu (GameTooltip, comparaisons,
    liens d objets) et la notre :
      - fond du theme a la place de la bordure de Blizzard (NineSlice) ;
      - liseré colore : classe du joueur survole, qualite de l objet,
        hostile / neutre / amical pour une creature ;
      - barre de vie au style CorpUI (hauteur, pourcentage) ;
      - position : celle de Blizzard, au curseur ou sur une ancre deplacable ;
      - masquage en combat (unites ou tout), Maj pour la voir quand meme ;
      - bandeau d infos en plus sous l infobulle : cible de l unite, guilde
        et rang, niveau d objet, ID de l objet, ID des sorts et PNJ, lignes des
        autres modules (ns.tipItemProviders : prix de l HV) ;
      - taille du texte des infobulles.

    Rien n est accroche au traitement des infobulles de Blizzard (les donnees
    d unite y sont protegees sur ce client) : pas de remplacement ni de
    hooksecurefunc (GameTooltip_SetDefaultAnchor...), pas de
    TooltipDataProcessor (il appelle notre code au milieu de ProcessInfo),
    pas d AddLine / Show sur leurs infobulles (Show relance leur OnShow
    depuis notre code). On lit l infobulle affichee depuis notre propre
    releve (OnUpdate de notre cadre) et on ne touche qu a l apparence :
    position (SetPoint), transparence (SetAlpha), et nos propres cadres.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L

local issecret = issecretvalue or function() return false end
local TIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
               "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip", "CorpUITooltip",
               "CorpUICompareTooltip1", "CorpUICompareTooltip2" }
-- infobulles qui recoivent le bandeau d infos en plus (CorpUITooltip :
-- sacs, banque, butin et metiers de CorpUI)
local EXTRA_TIPS = { "GameTooltip", "ItemRefTooltip", "CorpUITooltip" }
-- lignes d objet fournies par d autres modules (prix de l HV...) :
-- fn(infobulle, lien, lignes) ajoute ses textes a la liste
ns.tipItemProviders = ns.tipItemProviders or {}

local db
local skinned = {}       -- infobulle -> notre fond
local strips = {}        -- infobulle -> bandeau d infos
local barText = {}       -- barre de vie -> texte du pourcentage
local ours = {}          -- infobulle -> true quand c est nous qui l avons placee
local faded = {}         -- infobulle -> true quand masquee en combat (alpha 0)
local anchor             -- ancre deplacable (cree a la demande)

-- valeur lisible : ni erreur ni valeur secrete
local function safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c = pcall(fn, ...)
    if not ok or issecret(a) then return end
    return a, (not issecret(b)) and b or nil, (not issecret(c)) and c or nil
end

-- NineSlice et barre de vie : cherches une fois par infobulle
local nsOf, sbOf = {}, {}
local function getNineSlice(t) return t.NineSlice end
local function getStatusBar(t) return t.StatusBar end

local function nineSlice(tip)
    local n = nsOf[tip]
    if n then return n end
    local ok
    ok, n = pcall(getNineSlice, tip)
    if ok and type(n) == "table" and n.SetAlpha then
        nsOf[tip] = n
        return n
    end
end

local function statusBar(tip)
    local sb = sbOf[tip]
    if sb then return sb end
    local ok
    ok, sb = pcall(getStatusBar, tip)
    if ok and type(sb) == "table" and sb.SetStatusBarTexture then
        sbOf[tip] = sb
        return sb
    end
end

-- hauteur de la barre de vie et taille de son texte
local function styleBar(tip)
    local sb = statusBar(tip)
    if not sb or not skinned[tip] then return end
    local h = db.barHeight or 6
    sb:SetHeight(h)
    local fs = barText[sb]
    if fs then
        local file = fs:GetFont()
        if file then pcall(fs.SetFont, fs, file, math.max(8, math.min(12, h + 1)), "OUTLINE") end
    end
end

local function skin(tip)
    local bg = CreateFrame("Frame", nil, tip, "BackdropTemplate")
    bg:SetAllPoints()
    bg:SetFrameLevel(math.max(0, tip:GetFrameLevel() - 1))
    ns.UI.SetBackdrop(bg, 0.94)
    ns.UI.Shadow(bg, 3)
    -- fine bande d accent en haut
    local C = ns.COLORS
    local top = bg:CreateTexture(nil, "ARTWORK")
    top:SetPoint("TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", -1, -1)
    top:SetHeight(18)
    ns.UI.Gradient(top, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0, C.violet[1], C.violet[2], C.violet[3], 0.22)
    skinned[tip] = bg
    -- barre de vie (GameTooltip)
    local sb = statusBar(tip)
    if sb then
        pcall(sb.SetStatusBarTexture, sb, ns.BAR_TEXTURE)
        sb:ClearAllPoints()
        sb:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 1, -2)
        sb:SetPoint("TOPRIGHT", tip, "BOTTOMRIGHT", -1, -2)
        local sbg = CreateFrame("Frame", nil, sb, "BackdropTemplate")
        sbg:SetPoint("TOPLEFT", -1, 1)
        ns.NoSnap(sbg)
        sbg:SetPoint("BOTTOMRIGHT", 1, -1)
        sbg:SetFrameLevel(math.max(0, sb:GetFrameLevel() - 1))
        ns.UI.SetBackdrop(sbg, 0.9)
        -- texte du pourcentage, sur notre propre cadre au-dessus de la barre
        local over = CreateFrame("Frame", nil, sb)
        over:SetAllPoints()
        over:SetFrameLevel(sb:GetFrameLevel() + 2)
        local fs = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", 0, 0)
        barText[sb] = fs
        styleBar(tip)
    end
end

-- couleur du liseré selon ce que montre l infobulle
local function borderColor(tip)
    local C = ns.COLORS
    -- objet : qualite
    if tip.GetItem then
        local ok, _, link = pcall(tip.GetItem, tip)
        if ok and type(link) == "string" then
            local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            local color = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
            local okQ, _, _, q = pcall(info, link)
            if issecret(q) then q = nil end
            if okQ and q and q >= 2 and color then
                local okC, r, g, b = pcall(color, q)
                if okC and r then return r, g, b end
            end
        end
    end
    -- unite : classe d un joueur, sinon reaction
    if tip.GetUnit then
        local ok, _, unit = pcall(tip.GetUnit, tip)
        if ok and unit and not issecret(unit) then
            if ns.UF.Flag(UnitIsPlayer, unit) then
                local _, class = UnitClass(unit)
                if class and not issecret(class) and ns.ClassColor then return ns.ClassColor(class) end
            end
            local okR, r = pcall(UnitReaction, unit, "player")
            if okR and r and not issecret(r) then
                if r <= 3 then return 0.85, 0.2, 0.2 end
                if r == 4 then return 0.9, 0.8, 0.15 end
                return 0.25, 0.8, 0.3
            end
        end
    end
    return C.border[1], C.border[2], C.border[3]
end

local function scan()
    for _, name in ipairs(TIPS) do
        local tip = _G[name]
        if type(tip) == "table" and tip.GetObjectType and not skinned[tip] then
            pcall(skin, tip)
        end
    end
end

-- unite montree par l infobulle (jamais une valeur secrete)
local function tipUnit(tip)
    if not tip.GetUnit then return end
    local ok, _, unit = pcall(tip.GetUnit, tip)
    if ok and type(unit) == "string" and not issecret(unit) then return unit end
end

---------------------------------------------------------------------------
-- Position : on replace l infobulle apres coup, seulement quand Blizzard
-- l a posee a sa place par defaut (coin bas droit / conteneur du mode
-- edition). GameTooltip_SetDefaultAnchor n est ni remplace ni accroche.
---------------------------------------------------------------------------

local function editModeActive()
    local em = EditModeManagerFrame
    if type(em) ~= "table" or not em.IsEditModeActive then return false end
    local ok, v = pcall(em.IsEditModeActive, em)
    return ok and not issecret(v) and v and true or false
end

local function firstPoint(tip)
    local ok, point, rel = pcall(tip.GetPoint, tip, 1)
    if not ok or issecret(point) or issecret(rel) then return end
    return point, rel
end

local function isDefaultAnchor(rel)
    if not rel then return false end
    return rel == GameTooltipDefaultContainer or rel == SharedTooltipDefaultContainer
end

local function ensureAnchor()
    if anchor then return anchor end
    anchor = CreateFrame("Frame", "CorpUITooltipAnchor", UIParent)
    anchor:SetSize(200, 80)
    ns.ApplyPos(anchor, db.anchorPos)
    ns.UI.Mover(anchor, db.anchorPos, L.MOD_TIPS)
    return anchor
end

-- coin de l ancre le plus proche du bord de l ecran
local function anchorCorner()
    local cx, cy = anchor:GetCenter()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if not cx or not w or not h then return "BOTTOMRIGHT" end
    return (cy > h / 2 and "TOP" or "BOTTOM") .. (cx > w / 2 and "RIGHT" or "LEFT")
end

local function place(tip)
    local mode = db.anchor
    if mode ~= "cursor" and mode ~= "mover" then ours[tip] = nil return end
    if editModeActive() then return end
    local point, rel = firstPoint(tip)
    if isDefaultAnchor(rel) then
        ours[tip] = true
    elseif ours[tip] then
        -- quelqu un d autre l a reposee ailleurs : on la lui laisse
        local mine = (mode == "cursor" and rel == UIParent) or (mode == "mover" and rel == anchor)
        if not mine then ours[tip] = nil end
    end
    if not ours[tip] then return end
    if mode == "cursor" then
        local s = safe(tip.GetEffectiveScale, tip)
        local x, y = GetCursorPosition()
        if type(s) ~= "number" or s == 0 or not x then return end
        tip:ClearAllPoints()
        tip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s + 16, y / s + 12)
    else
        ensureAnchor()
        local corner = anchorCorner()
        if point ~= corner or rel ~= anchor then
            tip:ClearAllPoints()
            tip:SetPoint(corner, anchor, corner, 0, 0)
        end
    end
end

---------------------------------------------------------------------------
-- Masquage en combat : transparence seulement (Hide relancerait le OnHide
-- de Blizzard depuis notre code). Maj enfoncee : on la montre quand meme.
---------------------------------------------------------------------------

local function combatHide(tip, isMain)
    local mode = db.combatHide
    local hide = false
    if (mode == "units" or mode == "all") and InCombatLockdown() and not IsShiftKeyDown() and tip:IsShown() then
        if mode == "all" then
            hide = true
        elseif isMain then
            hide = tipUnit(tip) ~= nil
        end
    end
    if hide then
        local a = safe(tip.GetAlpha, tip)
        if type(a) ~= "number" or a > 0 then tip:SetAlpha(0) end
        faded[tip] = true
    elseif faded[tip] then
        faded[tip] = nil
        tip:SetAlpha(1)
    end
end

---------------------------------------------------------------------------
-- Bandeau d infos en plus (notre cadre, colle sous l infobulle)
---------------------------------------------------------------------------

local function hex(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function unitColor(unit)
    if ns.UF.Flag(UnitIsPlayer, unit) then
        local _, class = safe(UnitClass, unit)
        if class and ns.ClassColor then return hex(ns.ClassColor(class)) end
    end
    return "|cffffffff"
end

local function unitLines(unit, out)
    if db.showGuild and ns.UF.Flag(UnitIsPlayer, unit) then
        local guild, rank = safe(GetGuildInfo, unit)
        if type(guild) == "string" and guild ~= "" then
            local s = "|cff40ff40<" .. guild .. ">|r"
            if type(rank) == "string" and rank ~= "" then s = s .. "  |cffb0b0b0" .. rank .. "|r" end
            table.insert(out, s)
        end
    end
    if db.showTarget then
        local t = unit .. "target"
        if safe(UnitExists, t) then
            local name = safe(UnitName, t)
            if type(name) == "string" and name ~= "" then
                local me = UnitIsUnit and safe(UnitIsUnit, t, "player")
                if me then
                    table.insert(out, L.TIPS_TARGET .. " |cffff4040" .. L.TIPS_YOU .. "|r")
                else
                    table.insert(out, L.TIPS_TARGET .. " " .. unitColor(t) .. name .. "|r")
                end
            end
        end
    end
end

-- le niveau d objet est-il deja ecrit dans l infobulle ?
local function hasLine(tip, text)
    local name = tip.GetName and tip:GetName()
    local n = safe(tip.NumLines, tip)
    if not name or type(n) ~= "number" then return false end
    for i = 1, n do
        local fs = _G[name .. "TextLeft" .. i]
        if type(fs) == "table" and fs.GetText then
            local t = safe(fs.GetText, fs)
            if type(t) == "string" and t:find(text, 1, true) then return true end
        end
    end
    return false
end

local function itemLines(tip, link, out)
    if db.showIlvl then
        local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        -- nom, lien, qualite, niveau, niveau requis, type, sous-type, pile, emplacement
        local ok, _, _, _, base, _, _, _, _, equipLoc = pcall(info, link)
        if not ok then base, equipLoc = nil, nil end
        if type(equipLoc) == "string" and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
            local detail = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
            local lvl = safe(detail, link) or base
            if type(lvl) == "number" and not issecret(lvl) and lvl > 1 then
                local already = type(ITEM_LEVEL) == "string" and hasLine(tip, string.format(ITEM_LEVEL, lvl))
                if not already then table.insert(out, L.TIPS_ILVL .. " |cffffd100" .. lvl .. "|r") end
            end
        end
    end
    if db.showItemId then
        local id = link:match("item:(%d+)")
        if id then table.insert(out, L.TIPS_ITEM_ID .. " |cffffffff" .. id .. "|r") end
    end
end

-- identifiant de ce que montre l infobulle (sort, aura, PNJ...)
local function idLine(tip, out)
    local data = tip.GetPrimaryTooltipData and safe(tip.GetPrimaryTooltipData, tip)
    if type(data) ~= "table" then
        if tip.GetSpell then
            local _, id = safe(tip.GetSpell, tip)
            if type(id) == "number" then table.insert(out, L.TIPS_SPELL_ID .. " |cffffffff" .. id .. "|r") end
        end
        return
    end
    local okT, kind = pcall(function() return data.type end)
    local okI, id = pcall(function() return data.id end)
    if not okT or kind == nil or issecret(kind) then return end
    if not okI or issecret(id) then id = nil end
    local T = Enum and Enum.TooltipDataType or {}
    if (kind == T.Spell or kind == T.UnitAura or kind == T.Totem or kind == T.Macro) and type(id) == "number" and id > 0 then
        table.insert(out, L.TIPS_SPELL_ID .. " |cffffffff" .. id .. "|r")
    elseif kind == T.Unit then
        local okG, guid = pcall(function() return data.guid end)
        if okG and type(guid) == "string" and not issecret(guid) then
            local npc = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)") or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)")
            if npc then table.insert(out, L.TIPS_NPC_ID .. " |cffffffff" .. npc .. "|r") end
        end
    end
end

local EMPTY = {}

local function extraLines(tip)
    local out = {}
    local unit = tipUnit(tip)
    if unit then
        unitLines(unit, out)
        if db.showIds then idLine(tip, out) end
        return out
    end
    local link
    if tip.GetItem then
        local ok, _, l = pcall(tip.GetItem, tip)
        if ok and type(l) == "string" and not issecret(l) then link = l end
    end
    if link then
        -- (les fournisseurs de prix gardent leurs propres reponses : pile,
        -- sacs et minute compris)
        itemLines(tip, link, out)
        for _, fn in ipairs(ns.tipItemProviders) do pcall(fn, tip, link, out) end
    elseif db.showIds then
        idLine(tip, out)
    end
    return out
end

local function getStrip(tip)
    local s = strips[tip]
    if s then return s end
    s = CreateFrame("Frame", nil, tip, "BackdropTemplate")
    ns.UI.SetBackdrop(s, 0.94)
    s.text = s:CreateFontString(nil, "OVERLAY", "GameTooltipText")
    s.text:SetPoint("TOPLEFT", 6, -4)
    s.text:SetJustifyH("LEFT")
    s:Hide()
    strips[tip] = s
    return s
end

local function updateStrip(tip, r, g, b)
    local lines = (tip:IsShown() and extraLines(tip)) or EMPTY
    local s = strips[tip]
    if #lines == 0 then
        if s then s:Hide() s.lastText = nil end
        return
    end
    s = getStrip(tip)
    -- tailles lues avec prudence : elles peuvent etre secretes sur ce client
    local w = safe(tip.GetWidth, tip)
    if type(w) ~= "number" then w = 160 end
    local text = table.concat(lines, "\n")
    -- sous la barre de vie si elle est la, au-dessus si on sortirait de l ecran
    local gap = 2
    local sb = statusBar(tip)
    if sb and sb:IsShown() then gap = gap + (db.barHeight or 6) + 2 end
    local bottom = safe(tip.GetBottom, tip)
    if text ~= s.lastText or w ~= s.lastW then
        s.lastText, s.lastW = text, w
        s.text:SetWidth(math.max(60, w - 12))
        s.text:SetText(text)
        local th = s.text:GetStringHeight()
        s.h = ((type(th) == "number" and th > 0) and th or (#lines * 14)) + 8
        s:SetHeight(s.h)
        s.place = nil
    end
    local up = type(bottom) == "number" and bottom - gap - s.h < 0
    local place = (up and "up" or "down") .. gap
    if s.place ~= place then
        s.place = place
        s:ClearAllPoints()
        if up then
            s:SetPoint("BOTTOMLEFT", tip, "TOPLEFT", 0, 2)
            s:SetPoint("BOTTOMRIGHT", tip, "TOPRIGHT", 0, 2)
        else
            s:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 0, -gap)
            s:SetPoint("TOPRIGHT", tip, "BOTTOMRIGHT", 0, -gap)
        end
    end
    if r then s:SetBackdropBorderColor(r, g, b, 1) end
    s:Show()
end

-- pourcentage de vie (rien si la valeur est secrete)
local function updateBarText(tip)
    local sb = statusBar(tip)
    local fs = sb and barText[sb]
    if not fs then return end
    if not db.enabled or not db.barText or not sb:IsShown() then fs:SetText("") return end
    local v = safe(sb.GetValue, sb)
    local lo, hi = safe(sb.GetMinMaxValues, sb)
    if type(v) ~= "number" or type(lo) ~= "number" or type(hi) ~= "number" or hi <= lo then
        fs:SetText("")
        return
    end
    fs:SetText(math.floor((v - lo) / (hi - lo) * 100 + 0.5) .. "%")
end

---------------------------------------------------------------------------
-- Taille du texte : SetFont sur les objets police des infobulles (comme
-- Polices.lua) en gardant leur fichier ; Polices garde la taille courante.
---------------------------------------------------------------------------

local FONT_OBJECTS = { { "GameTooltipHeaderText", "header" }, { "GameTooltipText", "text" }, { "GameTooltipTextSmall", "small" } }
local baseSize = {}      -- objet police -> taille d origine

local function applyFonts()
    if not db.fontCustom and not next(baseSize) then return end    -- rien a faire ni a defaire
    for _, e in ipairs(FONT_OBJECTS) do
        local obj = _G[e[1]]
        if type(obj) == "table" and obj.GetFont and obj.SetFont then
            local ok, file, size, flags = pcall(obj.GetFont, obj)
            if ok and file and size then
                if not baseSize[obj] then baseSize[obj] = math.floor(size + 0.5) end
                local want = baseSize[obj]
                if db.fontCustom then
                    if e[2] == "header" then
                        want = db.headerSize
                    elseif e[2] == "text" then
                        want = db.textSize
                    else
                        want = math.max(6, db.textSize - 2)
                    end
                end
                if math.floor(size + 0.5) ~= want then pcall(obj.SetFont, obj, file, want, flags or "") end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Releve : un seul OnUpdate sur notre cadre
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local since, sinceExtra = 0, 0
local COMPARE_TIPS = { "ShoppingTooltip1", "ShoppingTooltip2", "CorpUICompareTooltip1", "CorpUICompareTooltip2" }
local lit = {}           -- infobulle -> couleur du bord posee depuis son affichage
local tipColor = {}      -- infobulle -> { r, g, b } (repris par le bandeau)
local function paintBorder(tip, bg)
    local r, g, b = borderColor(tip)
    local c = tipColor[tip]
    if not c then c = {} tipColor[tip] = c end
    c[1], c[2], c[3] = r, g, b
    bg:SetBackdropBorderColor(r, g, b, 1)
    lit[tip] = true
end
ev:SetScript("OnUpdate", function(_, dt)
    if not db then return end
    since = since + dt
    sinceExtra = sinceExtra + dt
    if since >= 2 then
        since = 0
        if db.enabled then scan() end
    end
    local tenth = sinceExtra >= 0.1
    if db.enabled then
        -- fond de Blizzard cache a chaque image ; bord a l affichage, puis
        -- dix fois par seconde (le contenu change sans que l infobulle se cache)
        for tip, bg in pairs(skinned) do
            if tip:IsShown() then
                local n = nineSlice(tip)
                if n and n:GetAlpha() > 0 then n:SetAlpha(0) end
                if tenth or not lit[tip] then paintBorder(tip, bg) end
            elseif lit[tip] then
                lit[tip] = nil
            end
        end
    end
    -- position et combat : a chaque image (avant l affichage)
    local gt = GameTooltip
    if type(gt) == "table" and gt.IsShown then
        if gt:IsShown() then place(gt) else ours[gt] = nil end
        combatHide(gt, true)
        for _, name in ipairs(COMPARE_TIPS) do
            local t = _G[name]
            if type(t) == "table" and t.SetAlpha then combatHide(t, false) end
        end
    end
    -- bandeau et texte de la barre : dix fois par seconde
    if tenth then
        sinceExtra = 0
        for _, name in ipairs(EXTRA_TIPS) do
            local tip = _G[name]
            if type(tip) == "table" and tip.IsShown then
                local c = skinned[tip] and tipColor[tip]
                local ok = pcall(updateStrip, tip, c and c[1], c and c[2], c and c[3])
                if not ok and strips[tip] then strips[tip]:Hide() end
                pcall(updateBarText, tip)
            end
        end
    end
end)
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if ns.ModuleOff("infobulles", ev) then return end
    local root = ns.InitRoot()
    root.tooltips = root.tooltips or {}
    db = root.tooltips
    if db.enabled == nil then db.enabled = true end
    -- nouvelles cles (les reglages existants ne bougent pas)
    if db.anchor == nil then db.anchor = "default" end
    if db.anchorPos == nil then db.anchorPos = { point = "BOTTOMRIGHT", x = -100, y = 160 } end
    if db.combatHide == nil then db.combatHide = "never" end
    if db.frameTips == nil then db.frameTips = true end
    if db.showTarget == nil then db.showTarget = true end
    if db.showGuild == nil then db.showGuild = true end
    if db.showIlvl == nil then db.showIlvl = true end
    if db.showIds == nil then db.showIds = false end
    -- 16/10 : l ID de l objet a sa propre case, allumee (avant : avec les ID des sorts et PNJ)
    if db.showItemId == nil then db.showItemId = true end
    if db.barHeight == nil then db.barHeight = 6 end
    if db.barText == nil then db.barText = true end
    if db.fontCustom == nil then db.fontCustom = false end
    if db.textSize == nil then db.textSize = 12 end
    if db.headerSize == nil then db.headerSize = 14 end
    if db.enabled then scan() end
    if db.anchor == "mover" then ensureAnchor() end
    applyFonts()
end)

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local win

local function apply()
    for tip in pairs(skinned) do styleBar(tip) end
    if db.anchor == "mover" then ensureAnchor() end
    applyFonts()
end

function ns.TipsOnFrames() return not db or db.frameTips ~= false end

local function toggle()
    if not win then
        win = ns.UI.Window("CorpUITooltipsOptions", ns.TITLE .. " - " .. L.MOD_TIPS, nil, 440, 140)
        local form = ns.UI.Form(win, -34, apply)
        local function check(key, text)
            form:Check(text, function() return db[key] end, function(v) db[key] = v end)
        end
        -- apparence
        form:Check(L.TIPS_OPT_ENABLE, function() return db.enabled end, function(v)
            db.enabled = v
            if v then scan() end
        end)
        form:Columns(2)
        form:Number(L.TIPS_BAR_HEIGHT, function() return db.barHeight end, function(v) db.barHeight = v end, 2, 16, 1)
        check("barText", L.TIPS_BAR_TEXT)
        form:EndColumns()
        -- position et combat
        form:Header(L.TIPS_POSITION)
        form:Columns(2)
        form:Cycle(L.TIPS_ANCHOR, { "default", "cursor", "mover" },
            { default = L.TIPS_ANCHOR_DEFAULT, cursor = L.TIPS_ANCHOR_CURSOR, mover = L.TIPS_ANCHOR_MOVER },
            function() return db.anchor end, function(v) db.anchor = v end)
        form:Cycle(L.TIPS_COMBAT, { "never", "units", "all" },
            { never = L.TIPS_COMBAT_NEVER, units = L.TIPS_COMBAT_UNITS, all = L.TIPS_COMBAT_ALL },
            function() return db.combatHide end, function(v) db.combatHide = v end)
        form:EndColumns()
        check("frameTips", L.TIPS_OPT_FRAMES)
        -- infos en plus
        form:Header(L.TIPS_EXTRA)
        form:Columns(2)
        check("showTarget", L.TIPS_OPT_TARGET)
        check("showGuild", L.TIPS_OPT_GUILD)
        check("showIlvl", L.TIPS_OPT_ILVL)
        check("showItemId", L.TIPS_OPT_ITEM_ID)
        check("showIds", L.TIPS_OPT_IDS)
        form:EndColumns()
        -- texte
        form:Header(L.TIPS_FONT)
        check("fontCustom", L.TIPS_OPT_FONT)
        form:Columns(2)
        form:Number(L.TIPS_FONT_TEXT, function() return db.textSize end, function(v) db.textSize = v end, 8, 20, 1)
        form:Number(L.TIPS_FONT_HEADER, function() return db.headerSize end, function(v) db.headerSize = v end, 8, 24, 1)
        form:EndColumns()
        local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 6)
        hint:SetWidth(420)
        hint:SetJustifyH("LEFT")
        hint:SetText(L.TIPS_HINT .. "\n" .. L.TIPS_HINT2)
        win:SetHeight(-form.y + 70)
        win:HookScript("OnShow", function() form:Refresh() end)
    end
    ns.ShowPanel(win)
end

ns.RegisterModule({
    command = "infobulles",
    alias = "tooltips",
    panelName = "CorpUITooltipsOptions",
    icon = "Interface\\Icons\\INV_Misc_Note_05",
    title = function() return L.MOD_TIPS end,
    desc = function() return L.TIPS_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})
