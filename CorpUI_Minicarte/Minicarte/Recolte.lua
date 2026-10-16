--[[--------------------------------------------------------------------------
    CorpUI - minicarte : icones des plantes, minerais et coffres

    Idee reprise de NodeSight (Krelock ; sans licence : l idee seulement, le
    code est ecrit pour CorpUI). Avec "Recherche d herbes", "Recherche de
    mineraux" ou "Recherche de tresors" (nain), la minicarte ne montre qu un
    point jaune par noeud. Ici, l icone de la plante, du minerai ou du coffre
    se pose sur le point.

    Un addon ne connait pas la position des noeuds, mais il peut lire les
    points de la minicarte : sa souris virtuelle (Minimap:
    UpdateMouseoverAtPoint) est promenee sur une grille, quelques points par
    image, et l infobulle de la minicarte (C_TooltipInfo.GetMinimapMouseover)
    nomme ce qui est dessous. Les points voisins qui donnent le meme nom font
    un noeud, a leur centre.

    Reconnaissance, dans toutes les langues :
      - plante : le noeud porte le nom de l objet (noms lus par le jeu a
        partir des numeros d objets ci-dessous) ;
      - minerai : le nom du filon contient le mot du metal, tire du nom du
        minerai ("Minerai de cuivre" -> "de cuivre", "Filon de cuivre") ;
      - coffre : recherche de tresors active ;
      - sinon (nom inconnu, recherche active) : icone generique du type.
    Les membres du groupe (points sur la minicarte aussi) sont ecartes.

    Entre deux balayages, les icones suivent le deplacement (position du
    monde du noeud, calculee au balayage) et la rotation de la minicarte.
    Pause : souris sur la minicarte (sa vraie infobulle), combat, aucune
    recherche active, minicarte cachee. Rien n est ecrit chez Blizzard.

    /corp minicarte recolte : diagnostic (recherches actives, noeuds vus).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local issecret = issecretvalue or function() return false end
local sqrt, floor, cos, sin = math.sqrt, math.floor, math.cos, math.sin

local R = {}
ns.MapNodes = R

local STEP = 8              -- pas de la grille (pixels de la minicarte)
local PER_FRAME = 40        -- points sondes par image
local INTERVAL = 1          -- secondes entre deux balayages
local FOLLOW = 0.05         -- les icones suivent le joueur 20 fois par seconde
local MAX_PINS = 40

-- sorts de recherche : herbes, mineraux, tresors (nain)
local FINDERS = { [2383] = "herb", [2580] = "ore", [2481] = "treasure" }
-- plantes de Classic (noeud = nom de l objet)
local HERBS = { 2447, 765, 2449, 785, 2450, 3820, 2453, 3355, 3369, 3356, 3357, 3818, 3821, 3358, 3819,
                4625, 8831, 8836, 8838, 8839, 8845, 8846, 13464, 13463, 13465, 13466, 13467, 13468 }
-- minerais (filons : le nom contient le mot du metal)
local ORES = { 2770, 2771, 2772, 2775, 2776, 3858, 7911, 10620, 11370, 3340, 4278, 5833 }
local GENERIC = {
    herb = { atlas = "Professions_Tracking_Herb", file = "Interface\\Icons\\INV_Misc_Flower_02" },
    ore = { atlas = "Professions_Tracking_Ore", file = "Interface\\Icons\\INV_Ore_Copper_01" },
    treasure = { file = "Interface\\Icons\\racial_dwarf_findtreasure" },
}

local function mdb() return ns.root and ns.root.map end
local function num(v) if type(v) == "number" and not issecret(v) then return v end end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end

---------------------------------------------------------------------------
-- Noms : plantes et metaux dans la langue du jeu
---------------------------------------------------------------------------

local herbByName, metals, namesReady = {}, {}, false

local function itemName(id)
    local n = C_Item and call(C_Item.GetItemNameByID, id)
    if type(n) == "string" and not issecret(n) and n ~= "" then return n end
    if C_Item and C_Item.RequestLoadItemDataByID then call(C_Item.RequestLoadItemDataByID, id) end
end

local function itemIcon(id)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local _, _, _, _, icon = call(fn, id)
    return num(icon) or (type(icon) == "string" and icon) or nil
end

local function words(s)
    local t = {}
    for w in s:gmatch("%S+") do t[#t + 1] = w end
    return t
end

-- partie propre a chaque nom : sans les mots (sinon les lettres) communs
-- a tous au debut et a la fin ("Minerai de cuivre" -> "de cuivre",
-- "Copper Ore" -> "Copper", "Kupfererz" -> "Kupfer")
local function distinctive(names)
    local lists = {}
    for i, n in ipairs(names) do lists[i] = words(n) end
    local pre, suf = 0, 0
    local function sameAt(get)
        local v = get(lists[1])
        if not v then return false end
        for i = 2, #lists do
            if get(lists[i]) ~= v then return false end
        end
        return true
    end
    while sameAt(function(w) return w[pre + 1] end) do pre = pre + 1 end
    while sameAt(function(w) return w[#w - suf] end) do suf = suf + 1 end
    local out = {}
    for i, w in ipairs(lists) do
        local part = table.concat(w, " ", pre + 1, #w - suf)
        out[i] = part ~= "" and part or nil
    end
    -- un seul mot par nom (allemand, chinois, coreen) : par les lettres
    local same = 0
    for i, n in ipairs(names) do
        if out[i] == n then same = same + 1 end
    end
    if same == #names then
        -- caracteres UTF-8 entiers (un caractere chinois fait 3 octets)
        local chars = {}
        for i, n in ipairs(names) do
            local t = {}
            for ch in n:gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = ch end
            chars[i] = t
        end
        local p, s = 0, 0
        local function common(get)
            local c = get(chars[1])
            if not c then return false end
            for i = 2, #chars do
                if get(chars[i]) ~= c then return false end
            end
            return true
        end
        while common(function(t) return t[p + 1] end) do p = p + 1 end
        while common(function(t) return t[#t - s] end) do s = s + 1 end
        for i, t in ipairs(chars) do
            local part = table.concat(t, "", p + 1, #t - s)
            out[i] = part ~= "" and part or nil
        end
    end
    return out
end
R.Distinctive = distinctive

local function loadNames()
    if namesReady then return true end
    local missing = false
    for _, id in ipairs(HERBS) do
        local n = itemName(id)
        if n then herbByName[n:lower()] = id else missing = true end
    end
    local oreNames, oreIds = {}, {}
    for _, id in ipairs(ORES) do
        local n = itemName(id)
        if n then
            oreNames[#oreNames + 1] = n
            oreIds[#oreIds + 1] = id
        else
            missing = true
        end
    end
    if #oreNames >= 3 then
        metals = {}
        for i, part in pairs(distinctive(oreNames)) do
            if part then metals[#metals + 1] = { word = part:lower(), id = oreIds[i] } end
        end
        -- le plus long d abord ("dark iron" avant "iron")
        table.sort(metals, function(a, b) return #a.word > #b.word end)
    end
    namesReady = not missing
    return namesReady
end

-- noms des membres du groupe (leurs points sont aussi sur la minicarte)
local function groupNames()
    local t = {}
    local n = num(call(GetNumGroupMembers)) or 0
    local prefix = (call(IsInRaid) and "raid") or "party"
    for i = 1, n do
        local name = call(UnitName, prefix .. i)
        if type(name) == "string" and not issecret(name) then t[name:lower()] = true end
    end
    return t
end

-- un nom vu sur la minicarte -> type et objet (nil : pas un noeud)
function R.Classify(name, finders, others)
    local low = name:lower()
    if others and others[low] then return nil end
    local herb = herbByName[low]
    if herb then return "herb", herb end
    if finders.ore then
        for _, m in ipairs(metals) do
            if low:find(m.word, 1, true) then return "ore", m.id end
        end
    end
    if finders.treasure then return "treasure" end
    -- nom inconnu : icone generique si une seule recherche est active
    local only, count = nil, 0
    for k in pairs(finders) do
        only, count = k, count + 1
    end
    if count == 1 then return only end
end

---------------------------------------------------------------------------
-- Recherches actives
---------------------------------------------------------------------------

local function activeFinders()
    local out = {}
    local M = C_Minimap
    if not (M and M.GetNumTrackingTypes and M.GetTrackingInfo) then return out end
    local n = num(call(M.GetNumTrackingTypes)) or 0
    for i = 1, n do
        local info = call(M.GetTrackingInfo, i)
        if type(info) == "table" and not issecret(info.spellID) and not issecret(info.active) then
            local kind = FINDERS[info.spellID]
            if kind and info.active == true then out[kind] = true end
        end
    end
    return out
end
R.ActiveFinders = activeFinders

---------------------------------------------------------------------------
-- Positions : minicarte <-> monde
---------------------------------------------------------------------------

local function vecXY(v)
    if type(v) ~= "table" then return nil end
    local x, y = v.x, v.y
    if (x == nil or y == nil) and v.GetXY then
        local ok, a, b = pcall(v.GetXY, v)
        if ok then x, y = a, b end
    end
    return num(x), num(y)
end

-- position monde du joueur : nord, ouest (nil en instance)
local function playerWorld()
    if not C_Map then return nil end
    local map = num(call(C_Map.GetBestMapForUnit, "player"))
    if not map then return nil end
    local x, y = vecXY(call(C_Map.GetPlayerMapPosition, map, "player"))
    if not x then return nil end
    local v = CreateVector2D and call(CreateVector2D, x, y) or { x = x, y = y }
    local cont, pos = call(C_Map.GetWorldPosFromMapPos, map, v)
    local n, w = vecXY(pos)
    if num(cont) and n then return cont, n, w end
end

local function rotating()
    local v = C_CVar and call(C_CVar.GetCVar, "rotateMinimap") or call(GetCVar, "rotateMinimap")
    return v == "1"
end

-- (dx, dy) : pixels depuis le centre (droite, haut) -> metres (nord, ouest)
function R.ToWorld(dx, dy, ypp, facing)
    if facing then
        local c, s = cos(facing), sin(facing)
        return (dy * c + dx * s) * ypp, (dy * s - dx * c) * ypp
    end
    return dy * ypp, -dx * ypp
end

-- metres (nord, ouest) -> pixels depuis le centre (droite, haut)
function R.ToMap(north, west, ypp, facing)
    if facing then
        local c, s = cos(facing), sin(facing)
        return (s * north - c * west) / ypp, (c * north + s * west) / ypp
    end
    return -west / ypp, north / ypp
end

---------------------------------------------------------------------------
-- Icones sur la minicarte
---------------------------------------------------------------------------

local layer
local pins, nodes = {}, {}

local function pin(i)
    local p = pins[i]
    if p then return p end
    p = CreateFrame("Frame", nil, layer)
    p:EnableMouse(false)          -- la vraie infobulle de la minicarte reste au survol
    p.edge = p:CreateTexture(nil, "ARTWORK", nil, 0)
    p.edge:SetAllPoints()
    p.edge:SetColorTexture(0, 0, 0, 0.9)
    p.icon = p:CreateTexture(nil, "ARTWORK", nil, 1)
    p.icon:SetPoint("TOPLEFT", 1, -1)
    p.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    pins[i] = p
    return p
end

local function setIcon(p, node)
    if node.item then
        local icon = itemIcon(node.item)
        if icon then
            p.icon:SetTexture(icon)
            p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            return
        end
    end
    local g = GENERIC[node.kind]
    p.icon:SetTexCoord(0, 1, 0, 1)
    if not (g.atlas and pcall(p.icon.SetAtlas, p.icon, g.atlas)) then
        p.icon:SetTexture(g.file)
        p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- place des icones : depuis leur position monde (le joueur bouge), sinon
-- la place du dernier balayage
local function place()
    if not layer then return end
    local d = mdb()
    local size = (d and d.nodeSize) or 14
    local half = (Minimap:GetWidth() or 140) / 2
    local radius = C_Minimap and num(call(C_Minimap.GetViewRadius))
    local ypp = radius and half > 0 and radius / half
    local facing = rotating() and num(call(GetPlayerFacing)) or nil
    local cont, pn, pw = playerWorld()
    -- minicarte carree (module Minicarte) ou ronde (celle du jeu)
    local square = type(GetMinimapShape) == "function" and GetMinimapShape() == "SQUARE"
    local shown = 0
    for i, node in ipairs(nodes) do
        local dx, dy = node.dx, node.dy
        if ypp and cont and node.cont == cont and node.north then
            dx, dy = R.ToMap(node.north - pn, node.west - pw, ypp, facing)
        end
        local p = pin(i)
        local edge = half - size / 4
        local inside
        if square then
            inside = math.abs(dx) <= edge and math.abs(dy) <= edge
        else
            inside = dx * dx + dy * dy <= edge * edge
        end
        if inside then
            if p.node ~= node then
                p.node = node
                setIcon(p, node)
            end
            p:SetSize(size, size)
            p:ClearAllPoints()
            p:SetPoint("CENTER", Minimap, "CENTER", dx, dy)
            p:Show()
            shown = shown + 1
        else
            p:Hide()
        end
    end
    for i = #nodes + 1, #pins do
        pins[i]:Hide()
        pins[i].node = nil
    end
    R.shown = shown
end

---------------------------------------------------------------------------
-- Balayage
---------------------------------------------------------------------------

local scan            -- balayage en cours : { points, next, hits, finders }
local wait = 0
local followWait = 0
local grid, gridWidth
R.last = { names = {}, count = 0 }

local function splitNames(text, out)
    for part in text:gsub("|n", "\n"):gmatch("[^\n]+") do
        part = part:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
        if part ~= "" and not part:find("[%d:/]") then out[#out + 1] = part end
    end
end

local function probe(left, bottom, scale, gx, gy, hits)
    pcall(Minimap.UpdateMouseoverAtPoint, Minimap, (left + gx) * scale, (bottom + gy) * scale)
    local data = C_TooltipInfo and call(C_TooltipInfo.GetMinimapMouseover)
    local lines = type(data) == "table" and not issecret(data) and data.lines
    if type(lines) ~= "table" or issecret(lines) then return end
    for _, line in ipairs(lines) do
        local text = type(line) == "table" and line.leftText
        if type(text) == "string" and not issecret(text) then
            local names = {}
            splitNames(text, names)
            for _, n in ipairs(names) do
                hits[n] = hits[n] or {}
                hits[n][#hits[n] + 1] = { gx, gy }
            end
        end
    end
end

local function startScan(finders)
    local w = floor(Minimap:GetWidth() or 0)
    if w <= 0 then return end
    if gridWidth ~= w then
        gridWidth, grid = w, {}
        for x = STEP / 2, w, STEP do
            for y = STEP / 2, w, STEP do grid[#grid + 1] = { x, y } end
        end
    end
    scan = { next = 1, hits = {}, finders = finders }
end

-- points voisins d un meme nom : un noeud par groupe, a son centre
local function cluster(points)
    local groups, used = {}, {}
    for i = 1, #points do
        if not used[i] then
            local g, stack = {}, { i }
            used[i] = true
            while #stack > 0 do
                local k = table.remove(stack)
                g[#g + 1] = points[k]
                for j = 1, #points do
                    if not used[j] and math.abs(points[j][1] - points[k][1]) <= STEP * 1.01
                        and math.abs(points[j][2] - points[k][2]) <= STEP * 1.01 then
                        used[j] = true
                        stack[#stack + 1] = j
                    end
                end
            end
            groups[#groups + 1] = g
        end
    end
    return groups
end
R.Cluster = cluster

local function finishScan()
    local s = scan
    scan = nil
    loadNames()
    local others = groupNames()
    local half = (Minimap:GetWidth() or 140) / 2
    local radius = C_Minimap and num(call(C_Minimap.GetViewRadius))
    local ypp = radius and half > 0 and radius / half
    local facing = rotating() and num(call(GetPlayerFacing)) or nil
    local cont, pn, pw = playerWorld()
    local found = {}
    R.last = { names = {}, count = 0 }
    for name, points in pairs(s.hits) do
        local kind, item = R.Classify(name, s.finders, others)
        R.last.names[name] = kind or "-"
        if kind then
            for _, g in ipairs(cluster(points)) do
                local sx, sy = 0, 0
                for _, p in ipairs(g) do
                    sx, sy = sx + p[1], sy + p[2]
                end
                local node = { name = name, kind = kind, item = item, dx = sx / #g - half, dy = sy / #g - half }
                if ypp and cont then
                    local n, w = R.ToWorld(node.dx, node.dy, ypp, facing)
                    node.cont, node.north, node.west = cont, pn + n, pw + w
                end
                found[#found + 1] = node
            end
        end
    end
    table.sort(found, function(a, b) return a.dx * a.dx + a.dy * a.dy < b.dx * b.dx + b.dy * b.dy end)
    while #found > MAX_PINS do table.remove(found) end
    nodes = found
    R.last.count = #found
    place()
end

local function clear()
    scan = nil
    if #nodes > 0 then
        nodes = {}
        place()
    end
end

local function canScan()
    local d = mdb()
    if not (d and d.nodes ~= false) then return false end
    if not (Minimap and Minimap.UpdateMouseoverAtPoint and Minimap:IsVisible()) then return false end
    if InCombatLockdown() then return false end
    -- souris sur la minicarte : sa vraie infobulle d abord
    if Minimap:IsMouseOver() then return false end
    return true
end

local function onUpdate(_, elapsed)
    followWait = followWait - elapsed
    if followWait <= 0 then
        followWait = FOLLOW
        if #nodes > 0 then place() end
    end
    if scan then
        if not canScan() then
            scan = nil
            return
        end
        local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
        local scale = Minimap:GetEffectiveScale()
        if not (left and bottom and scale) then
            scan = nil
            return
        end
        for _ = 1, PER_FRAME do
            local pt = grid[scan.next]
            if not pt then
                finishScan()
                return
            end
            probe(left, bottom, scale, pt[1], pt[2], scan.hits)
            scan.next = scan.next + 1
        end
        return
    end
    wait = wait - elapsed
    if wait > 0 then return end
    wait = INTERVAL
    local finders = activeFinders()
    if not next(finders) or not canScan() then
        if not next(finders) then clear() end
        return
    end
    startScan(finders)
end
R._update = onUpdate

-- calque pose sur la minicarte (au-dessus de ses points)
local function setup()
    if layer or not Minimap then return end
    layer = CreateFrame("Frame", nil, Minimap)
    layer:SetAllPoints(Minimap)
    layer:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)
    layer:SetScript("OnUpdate", onUpdate)
end

function ns.MapNodesRefresh()
    if not layer then return end
    local d = mdb()
    layer:SetShown(d and d.nodes ~= false)
    for _, p in ipairs(pins) do p.node = nil end
    place()
end

---------------------------------------------------------------------------
-- Diagnostic : /corp minicarte recolte
---------------------------------------------------------------------------

function ns.MapNodesDiag()
    local f = activeFinders()
    local list = {}
    for k in pairs(f) do list[#list + 1] = k end
    loadNames()
    local herbs = 0
    for _ in pairs(herbByName) do herbs = herbs + 1 end
    ns.Say(string.format(L.MAP_NODES_DIAG, #list > 0 and table.concat(list, ", ") or "-", R.last.count or 0,
        R.shown or 0, herbs, #metals))
    for name, kind in pairs(R.last.names or {}) do ns.Chat("    " .. name .. " : " .. kind) end
    for _, m in ipairs(metals) do ns.Chat("    metal : " .. m.word) end
end

---------------------------------------------------------------------------
-- Reglages : section dans le panneau de la minicarte
---------------------------------------------------------------------------

ns.MapOptionsHooks = ns.MapOptionsHooks or {}
table.insert(ns.MapOptionsHooks, function(form)
    form:Gap(4)
    form:Header(L.MAP_H_NODES)
    form:Columns(2)
    form:Check(L.MAP_OPT_NODES, function() return mdb() and mdb().nodes ~= false end, function(v)
        mdb().nodes = v
        if not v then clear() end
        ns.MapNodesRefresh()
    end)
    form:Number(L.MAP_NODES_SIZE, function() return (mdb() and mdb().nodeSize) or 14 end, function(v)
        mdb().nodeSize = v
        ns.MapNodesRefresh()
    end, 10, 24, 1)
    form:EndColumns()
end)

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("minicarte", ev) then return end
    if event == "PLAYER_LOGIN" then
        local d = ns.InitRoot().map
        if type(d) ~= "table" then
            ns.root.map = ns.root.map or {}
            d = ns.root.map
        end
        if d.nodes == nil then d.nodes = true end
        d.nodeSize = d.nodeSize or 14
        setup()
        loadNames()
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        if not namesReady then loadNames() end
    elseif event == "MINIMAP_UPDATE_TRACKING" or event == "MINIMAP_UPDATE_ZOOM" then
        wait = 0            -- recherche ou zoom change : nouveau balayage
    elseif event == "PLAYER_REGEN_DISABLED" then
        scan = nil
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "ITEM_DATA_LOAD_RESULT", "MINIMAP_UPDATE_TRACKING", "MINIMAP_UPDATE_ZOOM",
                     "PLAYER_REGEN_DISABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
