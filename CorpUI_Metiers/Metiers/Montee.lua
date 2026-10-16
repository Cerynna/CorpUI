--[[--------------------------------------------------------------------------
    CorpUI - module Metiers : montee de la competence

    Fonctions reprises de skillup-forever (cjber, GPL-3.0 : les idees, le
    code est ecrit pour CorpUI ; les chiffres viennent des tables du jeu,
    Donnees.lua, genere par .github/scripts/metiers_donnees.js) :
      - seuils de chaque recette : orange (= competence requise), jaune,
        vert (milieu de jaune et gris), gris ;
      - chance de monter d un point (formule de Classic) : 100 % en
        orange ; de jaune a gris (gris - competence) / (gris - jaune) ;
        0 % en gris ;
      - cout d une fabrication (composants) et cout par point gagne
        (cout / (chance x points par fabrication)).
    Prix d un composant : chez un marchand (prix releve a chaque visite,
    ou fourniture connue : fils, flux, fioles, epices, teintures...), sinon
    la valeur du marche du module Hotel des ventes ; ce que tu recoltes
    toi-meme (herboristerie, minage, depecage) compte comme gratuit (option).

    Affichage :
      - a droite de chaque ligne de la liste des recettes de Blizzard :
        chance et cout par point (cadres a nous poses sur ses lignes,
        lecture seule de leurs donnees, aucun crochet) ;
      - onglet "Montee" du volet CorpUI des metiers : la recette choisie
        (barre des seuils, ta competence marquee, cout et composants), puis
        les recettes apprises qui font encore monter, triees par cout par
        point ou par chance.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local M = ns.Craft
local issecret = issecretvalue or function() return false end

local S = {}
ns.CraftSkill = S

local function num(v) if type(v) == "number" and not issecret(v) then return v end end
local function str(v) if type(v) == "string" and not issecret(v) and v ~= "" then return v end end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end
local function TS(fn, ...)
    local f = C_TradeSkillUI and C_TradeSkillUI[fn]
    local a = call(f, ...)
    if not issecret(a) then return a end
end
local function field(t, key)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok and not issecret(v) then return v end
end

local db
local function DB()
    if not db and M and M.DB then db = M.DB() end
    return db
end

---------------------------------------------------------------------------
-- Donnees : recettes et objets (Donnees.lua), decodes a la demande
---------------------------------------------------------------------------

local recCache, itemCache = {}, {}

-- recette : { skill, min, yellow, green, gray, item, count, acquire, ups, reagents = { { objet, n } } }
function S.Recipe(id)
    id = num(id)
    if not id then return nil end
    local r = recCache[id]
    if r ~= nil then return r or nil end
    local raw = ns.CraftData and ns.CraftData.recipes[id]
    if type(raw) ~= "string" then
        recCache[id] = false
        return nil
    end
    local f = {}
    for v in (raw .. ","):gmatch("([^,]*),") do f[#f + 1] = v end
    r = { skill = tonumber(f[1]), min = tonumber(f[2]) or 1, yellow = tonumber(f[3]) or 0, gray = tonumber(f[4]) or 0,
          item = tonumber(f[5]) or 0, count = tonumber(f[6]) or 1, acquire = tonumber(f[7]) or 0,
          ups = tonumber(f[8]) or 1, reagents = {} }
    r.green = math.floor((r.yellow + r.gray) / 2)
    for id2, n in (f[9] or ""):gmatch("(%d+):(%d+)") do r.reagents[#r.reagents + 1] = { tonumber(id2), tonumber(n) } end
    recCache[id] = r
    return r
end

-- objet : { buy, stack, sell, inv, ilvl, req, q, cls, sub }
function S.Item(id)
    id = num(id)
    if not id then return nil end
    local e = itemCache[id]
    if e ~= nil then return e or nil end
    local raw = ns.CraftData and ns.CraftData.items[id]
    if type(raw) ~= "string" then
        itemCache[id] = false
        return nil
    end
    local f = {}
    for v in (raw .. ","):gmatch("([^,]*),") do f[#f + 1] = tonumber(v) or 0 end
    e = { buy = f[1], stack = math.max(1, f[2]), sell = f[3], inv = f[4], ilvl = f[5], req = f[6], q = f[7],
          cls = f[8], sub = f[9] }
    itemCache[id] = e
    return e
end

-- couleur de la recette a cette competence : red (pas encore), orange,
-- yellow, green, gray
function S.Color(r, skill)
    if not (r and skill) then return nil end
    if skill < r.min then return "red" end
    if skill < r.yellow then return "orange" end
    if skill < r.green then return "yellow" end
    if skill < r.gray then return "green" end
    return "gray"
end

-- chance de gagner un point (0 a 1) ; nil : pas encore apprenable
function S.Chance(r, skill)
    if not (r and skill) then return nil end
    if skill < r.min then return nil end
    if skill < r.yellow then return 1 end
    if skill >= r.gray or r.gray <= r.yellow then return 0 end
    return (r.gray - skill) / (r.gray - r.yellow)
end

S.COLORS = {
    red = { 0.9, 0.25, 0.25 }, orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 },
    green = { 0.25, 0.75, 0.25 }, gray = { 0.55, 0.55, 0.55 },
}

---------------------------------------------------------------------------
-- Prix des composants
---------------------------------------------------------------------------

-- fournitures vendues partout (fils, flux, fioles, epices, teintures, sel,
-- bois, tige, lait, eau...) : prix d achat de la base, meme sans visite
local VENDOR = {
    [2320] = true, [2321] = true, [4291] = true, [8343] = true, [14341] = true, [2324] = true, [2604] = true,
    [2605] = true, [4340] = true, [4341] = true, [4342] = true, [6260] = true, [6261] = true, [10290] = true,
    [2325] = true, [4289] = true, [2880] = true, [3466] = true, [3371] = true, [3372] = true, [8925] = true,
    [18256] = true, [4470] = true, [6217] = true, [2678] = true, [2692] = true, [3713] = true, [159] = true,
    [1179] = true, [2894] = true, [3857] = true, [4399] = true, [4400] = true, [10647] = true, [10648] = true,
}
S.VENDOR = VENDOR

-- metier de recolte qui fournit cet objet (marchandises : herbe 9, metal et
-- pierre 7, cuir 6)
local GATHER = { [9] = 182, [7] = 186, [6] = 393 }

local function gatherProfs()
    local out = {}
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return out end
    local res = { pcall(GetProfessions) }
    if not res[1] then return out end
    for i = 2, 6 do
        local idx = num(res[i])
        if idx then
            -- 7e valeur : la ligne de competence (182 herboristerie...)
            local ok, _, _, _, _, _, _, line = pcall(GetProfessionInfo, idx)
            if ok and num(line) then out[line] = true end
        end
    end
    return out
end

-- prix unitaire d un objet (cuivre) et sa source : "vendor", "free", "ah" ;
-- nil si inconnu
function S.Price(item, gathered)
    local d = DB()
    local e = S.Item(item)
    local seen = d and d.vendor and d.vendor[item]
    if seen then return seen, "vendor" end
    if e and e.buy > 0 and VENDOR[item] then return e.buy / e.stack, "vendor" end
    if d and d.freeGathered ~= false and e and e.cls == 7 and GATHER[e.sub] then
        gathered = gathered or gatherProfs()
        if gathered[GATHER[e.sub]] then return 0, "free" end
    end
    if type(ns.AHPrice) == "function" then
        local p = call(ns.AHPrice, item)
        if num(p) then return p, "ah" end
    end
    return nil
end

-- cout d une fabrication : total des composants qui ont un prix, nombre
-- de composants sans prix, detail { { objet, n, prix, source } }
function S.Cost(r, gathered)
    local total, missing, parts = 0, 0, {}
    gathered = gathered or gatherProfs()
    for _, g in ipairs(r.reagents) do
        local p, src = S.Price(g[1], gathered)
        parts[#parts + 1] = { g[1], g[2], p, src }
        if p then total = total + p * g[2] else missing = missing + 1 end
    end
    return total, missing, parts
end

-- cout par point gagne (nil : ne fait plus monter, ou prix inconnu)
function S.PerPoint(r, skill, gathered)
    local c = S.Chance(r, skill)
    if not c or c <= 0 then return nil end
    local total, missing = S.Cost(r, gathered)
    if missing > 0 then return nil end
    return total / (c * math.max(1, r.ups))
end

-- prix des marchands : releves a chaque visite (objets de la base seulement)
local function recordMerchant()
    local d = DB()
    if not d or not ns.CraftData then return end
    d.vendor = d.vendor or {}
    local n = num(call(GetMerchantNumItems)) or 0
    for i = 1, n do
        local id = num(call(GetMerchantItemID, i))
        if id and ns.CraftData.items[id] then
            local price, qty
            if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                local info = call(C_MerchantFrame.GetItemInfo, i)
                if type(info) == "table" then price, qty = num(info.price), num(info.stackCount) end
            end
            if not price then
                local _, _, p, q = call(GetMerchantItemInfo, i)
                price, qty = num(p), num(q)
            end
            if price and price > 0 then d.vendor[id] = price / math.max(1, qty or 1) end
        end
    end
end
S.RecordMerchant = recordMerchant

---------------------------------------------------------------------------
-- Metier ouvert
---------------------------------------------------------------------------

-- competence du metier ouvert (avec le bonus racial) et son maximum
function S.CurrentSkill()
    for _, fn in ipairs({ "GetChildProfessionInfo", "GetBaseProfessionInfo" }) do
        local info = TS(fn)
        local lvl = type(info) == "table" and num(info.skillLevel)
        if lvl and lvl > 0 then
            return lvl + (num(info.skillModifier) or 0), num(info.maxSkillLevel) or 0,
                str(info.parentProfessionName) or str(info.professionName)
        end
    end
end

local function own() return not (M and M.OwnSkill) or M.OwnSkill() end

local function short(c)
    if not c then return nil end
    return (ns.AHMoney or ns.FormatMoney)(c)
end
S.Money = short

local function pct(c) return string.format("%d%%", math.floor(c * 100 + 0.5)) end

local function hex(c)
    return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

---------------------------------------------------------------------------
-- Lignes de la liste des recettes de Blizzard
---------------------------------------------------------------------------

local overlays = setmetatable({}, { __mode = "k" })

local function recipeList()
    local pf = rawget(_G, "ProfessionsFrame")
    local sb = field(field(field(pf, "CraftingPage"), "RecipeList"), "ScrollBox")
    if type(sb) ~= "table" then return nil end
    local ok, shown = pcall(sb.IsVisible, sb)
    if not ok or issecret(shown) or not shown then return nil end
    return sb
end

local function rowRecipe(frame)
    local get = field(frame, "GetElementData")
    if type(get) ~= "function" then return nil end
    local ok, d = pcall(get, frame)
    if not ok or type(d) ~= "table" or issecret(d) then return nil end
    local getData = field(d, "GetData")
    if type(getData) == "function" then
        local ok2, data = pcall(getData, d)
        d = ok2 and data or nil
    end
    local info = field(d, "recipeInfo")
    return num(field(info, "recipeID"))
end

local function overlay(frame)
    local o = overlays[frame]
    if o then return o end
    o = CreateFrame("Frame", nil, frame)
    o:SetAllPoints(frame)
    o:EnableMouse(false)
    o.text = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.text:SetPoint("RIGHT", -6, 0)
    o.text:SetJustifyH("RIGHT")
    overlays[frame] = o
    return o
end

-- texte d une ligne : "75% · 1pa 20" (chance, cout par point)
function S.RowText(r, skill, gathered)
    local col = S.Color(r, skill)
    if not col or col == "gray" then return nil end
    local c = S.Chance(r, skill)
    if not c then
        return "|cff" .. hex(S.COLORS.red) .. string.format(L.SKILL_ROW_REQ, r.min) .. "|r"
    end
    local text = "|cff" .. hex(S.COLORS[col]) .. pct(c) .. "|r"
    local pp = S.PerPoint(r, skill, gathered)
    if pp then text = text .. " |cffb0b0b0" .. short(pp) .. "|r" end
    return text
end

local function paintRows()
    local d = DB()
    local sb = recipeList()
    local on = sb and d and d.skillRows ~= false and own()
    local skill = on and S.CurrentSkill()
    local seen = {}
    if on and skill then
        local frames = call(sb.GetFrames, sb)
        local gathered = gatherProfs()
        for _, frame in ipairs(type(frames) == "table" and frames or {}) do
            local id = rowRecipe(frame)
            local r = id and S.Recipe(id)
            local text = r and S.RowText(r, skill, gathered)
            if text then
                local o = overlay(frame)
                o.text:SetText(text)
                o:Show()
                seen[o] = true
            end
        end
    end
    for _, o in pairs(overlays) do
        if not seen[o] then o:Hide() end
    end
end
S.PaintRows = paintRows

---------------------------------------------------------------------------
-- Onglet "Montee" du volet des metiers
---------------------------------------------------------------------------

local view
local LIST_H = 18
local MAX_PARTS = 6

local function sortedRecipes(skill, gathered)
    local out = {}
    local ids = TS("GetAllRecipeIDs")
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        local r = S.Recipe(id)
        local c = r and S.Chance(r, skill)
        if c and c > 0 then
            local info = TS("GetRecipeInfo", id)
            if type(info) == "table" and info.learned == true then
                out[#out + 1] = { id = id, r = r, chance = c, pp = S.PerPoint(r, skill, gathered),
                                  name = str(info.name) or ("#" .. id) }
            end
        end
    end
    local byChance = DB() and DB().skillSort == "chance"
    table.sort(out, function(a, b)
        if not byChance then
            if (a.pp ~= nil) ~= (b.pp ~= nil) then return a.pp ~= nil end
            if a.pp and b.pp and a.pp ~= b.pp then return a.pp < b.pp end
        end
        if a.chance ~= b.chance then return a.chance > b.chance end
        return a.name < b.name
    end)
    return out
end
S.Sorted = sortedRecipes

local function drawBar(r, skill)
    local b = view.bar
    local lo, hi = r.min, math.max(r.gray, r.min + 1)
    local w = b:GetWidth() or 200
    local function x(v) return (math.max(lo, math.min(hi, v)) - lo) / (hi - lo) * w end
    local segs = { { r.min, r.yellow, "orange" }, { r.yellow, r.green, "yellow" }, { r.green, r.gray, "green" } }
    for i, s in ipairs(segs) do
        local t = b.segs[i]
        local x1, x2 = x(s[1]), x(s[2])
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", b, "TOPLEFT", x1, 0)
        t:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", x1, 0)
        t:SetWidth(math.max(1, x2 - x1))
        local c = S.COLORS[s[3]]
        t:SetColorTexture(c[1], c[2], c[3], 0.9)
        t:SetShown(x2 > x1)
        local lab = b.labels[i]
        lab:ClearAllPoints()
        lab:SetPoint("TOP", b, "BOTTOMLEFT", x1, -2)
        lab:SetText(tostring(s[1]))
    end
    local last = b.labels[4]
    last:ClearAllPoints()
    last:SetPoint("TOP", b, "BOTTOMLEFT", w, -2)
    last:SetText(tostring(r.gray))
    b.marker:ClearAllPoints()
    b.marker:SetPoint("CENTER", b, "LEFT", x(skill), 0)
    b.marker:SetShown(skill >= lo - 0 and skill <= hi + 50)
end

local function refreshView()
    if not (view and view.frame:IsVisible()) then return end
    local skill, max, name = S.CurrentSkill()
    if not skill or not own() then
        view.head:SetText(L.SKILL_OPEN)
        view.block:Hide()
        for _, row in ipairs(view.rows) do row:Hide() end
        view.listHead:Hide()
        view.sort:Hide()
        return
    end
    view.head:SetText(string.format(L.SKILL_HEAD, name or "?", skill, max or 0))
    local gathered = gatherProfs()
    -- recette choisie
    local id = M and M.SelectedRecipe and M.SelectedRecipe()
    local r = id and S.Recipe(id)
    local y = -22
    if r then
        view.block:Show()
        local info = TS("GetRecipeInfo", id)
        view.name:SetText(type(info) == "table" and str(info.name) or ("#" .. id))
        drawBar(r, skill)
        local c = S.Chance(r, skill)
        local col = S.Color(r, skill)
        local cc = S.COLORS[col] or S.COLORS.gray
        if c then
            view.chance:SetText(string.format(L.SKILL_CHANCE, math.floor(c * 100 + 0.5)))
        else
            view.chance:SetText(string.format(L.SKILL_ROW_REQ, r.min))
        end
        view.chance:SetTextColor(cc[1], cc[2], cc[3])
        local total, missing, parts = S.Cost(r, gathered)
        local pp = S.PerPoint(r, skill, gathered)
        if missing > 0 then
            view.cost:SetText(string.format(L.SKILL_COST_PART, short(total), missing))
        elseif pp then
            view.cost:SetText(string.format(L.SKILL_COST, short(total), short(pp)))
        else
            view.cost:SetText(string.format(L.SKILL_COST_ONE, short(total)))
        end
        for i = 1, MAX_PARTS do
            local line, p = view.parts[i], parts[i]
            if p then
                local src = p[4] and L["SKILL_SRC_" .. p[4]:upper()] or L.SKILL_SRC_NONE
                local nm = ns.ItemName and ns.ItemName(p[1]) or ("item:" .. p[1])
                line.left:SetText(string.format("%d x %s", p[2], nm or "?"))
                line.right:SetText(p[3] and (short(p[3] * p[2]) .. " |cff909090" .. src .. "|r") or ("|cffff6666" .. src .. "|r"))
                line:Show()
            else
                line:Hide()
            end
        end
        y = -22 - (view.block.base + math.min(#parts, MAX_PARTS) * 14)
    else
        view.block:Hide()
    end
    -- recettes qui font monter
    view.listHead:ClearAllPoints()
    view.listHead:SetPoint("TOPLEFT", view.frame, "TOPLEFT", 4, y - 6)
    view.listHead:Show()
    view.sort:ClearAllPoints()
    view.sort:SetPoint("RIGHT", view.frame, "TOPRIGHT", -2, y - 12)
    view.sort:SetText(DB().skillSort == "chance" and L.SKILL_SORT_CHANCE or L.SKILL_SORT_COST)
    view.sort:Show()
    local list = sortedRecipes(skill, gathered)
    view.listHead:SetText(string.format(L.SKILL_LIST, #list))
    local top = y - 24
    local avail = math.max(1, math.floor(((view.frame:GetHeight() or 300) + top) / LIST_H))
    view.offset = math.max(0, math.min(view.offset or 0, #list - avail))
    for i, row in ipairs(view.rows) do
        local e = list[i + view.offset]
        if e and i <= avail then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", view.frame, "TOPLEFT", 0, top - (i - 1) * LIST_H)
            row:SetPoint("RIGHT", view.frame, "RIGHT", 0, 0)
            local col = S.COLORS[S.Color(e.r, skill)] or S.COLORS.gray
            row.left:SetText(e.name)
            row.left:SetTextColor(col[1], col[2], col[3])
            row.right:SetText(pct(e.chance) .. (e.pp and ("  " .. short(e.pp)) or ""))
            row.entry = e
            row:Show()
        else
            row:Hide()
            row.entry = nil
        end
    end
end
S.RefreshView = refreshView

local function rowTip(row)
    local e = row.entry
    if not e then return end
    local t = ns.Tooltip(row, "ANCHOR_LEFT")
    t:SetText(e.name)
    local skill = S.CurrentSkill() or 0
    t:AddLine(string.format("%d  %d  %d  %d", e.r.min, e.r.yellow, e.r.green, e.r.gray), 0.8, 0.8, 0.8)
    t:AddLine(string.format(L.SKILL_CHANCE, math.floor(e.chance * 100 + 0.5)), 1, 1, 1)
    local total, missing, parts = S.Cost(e.r)
    for _, p in ipairs(parts) do
        local nm = ns.ItemName and ns.ItemName(p[1]) or ("item:" .. p[1])
        local src = p[4] and L["SKILL_SRC_" .. p[4]:upper()] or L.SKILL_SRC_NONE
        t:AddDoubleLine(string.format("%d x %s", p[2], nm or "?"), p[3] and (short(p[3] * p[2]) .. " " .. src) or src,
            1, 1, 1, 0.8, 0.8, 0.8)
    end
    if missing == 0 and e.pp then t:AddLine(string.format(L.SKILL_COST, short(total), short(e.pp)), 1, 0.82, 0) end
    t:Show()
    local _ = skill
end

function M.BuildSkillView(parent)
    local C = ns.COLORS
    view = { rows = {}, parts = {}, offset = 0 }
    local f = CreateFrame("Frame", nil, parent)
    view.frame = f
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, d)
        view.offset = math.max(0, (view.offset or 0) - d * 3)
        refreshView()
    end)
    view.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.head:SetPoint("TOPLEFT", 4, -4)
    view.head:SetPoint("RIGHT", -4, 0)
    view.head:SetJustifyH("LEFT")

    -- recette choisie
    local block = CreateFrame("Frame", nil, f)
    block:SetPoint("TOPLEFT", 0, -22)
    block:SetPoint("RIGHT", 0, 0)
    block:SetHeight(1)
    view.block = block
    view.name = block:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    view.name:SetPoint("TOPLEFT", 4, 0)
    view.name:SetPoint("RIGHT", -4, 0)
    view.name:SetJustifyH("LEFT")
    view.name:SetWordWrap(false)
    local bar = CreateFrame("Frame", nil, block)
    bar:SetPoint("TOPLEFT", 12, -20)
    bar:SetPoint("RIGHT", -16, 0)
    bar:SetHeight(8)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:SetColorTexture(0, 0, 0, 0.8)
    bar.segs, bar.labels = {}, {}
    for i = 1, 3 do bar.segs[i] = bar:CreateTexture(nil, "ARTWORK") end
    for i = 1, 4 do
        local lab = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        bar.labels[i] = lab
    end
    bar.marker = bar:CreateTexture(nil, "OVERLAY")
    bar.marker:SetSize(3, 14)
    bar.marker:SetColorTexture(1, 1, 1, 1)
    view.bar = bar
    view.chance = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.chance:SetPoint("TOPLEFT", 4, -46)
    view.cost = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.cost:SetPoint("TOPLEFT", 4, -62)
    view.cost:SetPoint("RIGHT", -4, 0)
    view.cost:SetJustifyH("LEFT")
    block.base = 80
    for i = 1, MAX_PARTS do
        local line = CreateFrame("Frame", nil, block)
        line:SetHeight(14)
        line:SetPoint("TOPLEFT", 8, -78 - (i - 1) * 14)
        line:SetPoint("RIGHT", -4, 0)
        line.left = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.left:SetPoint("LEFT")
        line.left:SetJustifyH("LEFT")
        line.left:SetWordWrap(false)
        line.right = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.right:SetPoint("RIGHT")
        line.right:SetJustifyH("RIGHT")
        line.left:SetPoint("RIGHT", line.right, "LEFT", -4, 0)
        view.parts[i] = line
    end

    -- recettes qui font monter
    view.listHead = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    view.listHead:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    view.sort = ns.UI.Button(f, L.SKILL_SORT_COST, 90, function()
        local d = DB()
        d.skillSort = d.skillSort == "chance" and "cost" or "chance"
        refreshView()
    end)
    view.sort:SetHeight(18)
    for i = 1, 24 do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(LIST_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetPoint("RIGHT", -4, 0)
        row.right:SetJustifyH("RIGHT")
        row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.left:SetPoint("LEFT", 4, 0)
        row.left:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        row:SetScript("OnEnter", rowTip)
        row:SetScript("OnLeave", ns.HideTooltip)
        row:Hide()
        view.rows[i] = row
    end
    f:SetScript("OnShow", refreshView)
    f:Hide()
    return view
end

---------------------------------------------------------------------------
-- Reglages (panneau des metiers) et evenements
---------------------------------------------------------------------------

M.optionHooks = M.optionHooks or {}
table.insert(M.optionHooks, function(form, d)
    form:Check(L.SKILL_OPT_ROWS, function() return d.skillRows ~= false end, function(v) d.skillRows = v end)
    form:Check(L.SKILL_OPT_FREE, function() return d.freeGathered ~= false end, function(v) d.freeGathered = v end)
end)

-- recette choisie, liste, lignes : relus pendant que la fenetre est ouverte
local lastRecipe
ns.Every(0.25, function()
    if not DB() then return end
    if not recipeList() then return end
    local ok, err = pcall(paintRows)
    if not ok then geterrorhandler()(err) end
    local id = M.SelectedRecipe and M.SelectedRecipe()
    if id ~= lastRecipe then
        lastRecipe = id
        pcall(refreshView)
    end
end, "Metiers : montee", "metiers")

if M and M.listeners then
    table.insert(M.listeners, function() pcall(refreshView) end)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("metiers", ev) then return end
    if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        pcall(recordMerchant)
    elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "SKILL_LINES_CHANGED" or event == "TRADE_SKILL_SHOW" then
        pcall(refreshView)
    end
end)
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "TRADE_SKILL_LIST_UPDATE", "SKILL_LINES_CHANGED",
                     "TRADE_SKILL_SHOW" }) do
    pcall(ev.RegisterEvent, ev, e)
end
