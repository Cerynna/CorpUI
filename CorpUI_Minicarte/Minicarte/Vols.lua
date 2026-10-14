--[[
    CorpUI - points de vol sur la carte du monde
    Bleu : Alliance, rouge : Horde, vert : les deux factions.

    La carte du jeu ne montre que les points de notre faction. Ici, un
    calque a nous pose sur le canevas de la carte (WorldMapFrame.
    ScrollContainer.Child) : aucun fournisseur ajoute a la carte de
    Blizzard, aucun crochet, rien d ecrit chez elle. Les points viennent de
    C_TaxiMap.GetTaxiNodesForMap(carte), comme pour la carte du jeu.

    Le calque ne tourne que carte ouverte (OnUpdate d un cadre enfant du
    canevas) : il relit les points quand la carte change, et les replace
    quand le zoom change (taille constante a l ecran).

    /corp minicarte vols : diagnostic (carte, nombre de points par faction).
]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local issecret = issecretvalue or function() return false end

local COLORS = {
    alliance = { 0.25, 0.55, 1 },
    horde = { 1, 0.22, 0.22 },
    neutral = { 0.3, 0.9, 0.35 },
}
-- disque blanc a bord doux (teinte par la couleur de la faction)
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SIZE = 14

local function mdb() return ns.root and ns.root.map end

local layer
local pins, nodes = {}, {}
local lastMap, lastScale, lastW, lastH

local function factionOf(f)
    if issecret(f) then return "neutral" end
    local E = Enum and Enum.FlightPathFaction
    if E and E.Alliance ~= nil then
        if f == E.Alliance then return "alliance" end
        if f == E.Horde then return "horde" end
        return "neutral"
    end
    -- valeurs connues : 0 neutre, 1 Horde, 2 Alliance
    if f == 2 then return "alliance" elseif f == 1 then return "horde" end
    return "neutral"
end

local function myFaction()
    local ok, f = pcall(UnitFactionGroup, "player")
    if ok and not issecret(f) and f == "Horde" then return "horde" end
    return "alliance"
end

local function readXY(pos)
    if type(pos) ~= "table" then return nil end
    local x, y = pos.x, pos.y
    if (x == nil or y == nil) and pos.GetXY then
        local ok, a, b = pcall(pos.GetXY, pos)
        if ok then x, y = a, b end
    end
    if type(x) ~= "number" or type(y) ~= "number" or issecret(x) or issecret(y) then return nil end
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

-- carte du monde du jeu et son canevas (lecture seule)
local function canvas()
    local wm = _G.WorldMapFrame
    if type(wm) ~= "table" then return nil end
    local sc = wm.ScrollContainer
    local child = type(sc) == "table" and sc.Child or nil
    if type(child) ~= "table" or not child.GetWidth then return nil end
    return wm, sc, child
end

local function mapIDOf(wm)
    if not (wm and wm.GetMapID) then return nil end
    local ok, id = pcall(wm.GetMapID, wm)
    if ok and type(id) == "number" and not issecret(id) then return id end
end

local function canvasScale(sc, child)
    local s
    if sc and sc.GetCanvasScale then
        local ok, v = pcall(sc.GetCanvasScale, sc)
        if ok then s = v end
    end
    if type(s) ~= "number" or issecret(s) then
        local ok, v = pcall(child.GetScale, child)
        s = ok and v or 1
    end
    if type(s) ~= "number" or issecret(s) or s <= 0 then s = 1 end
    return s
end

---------------------------------------------------------------------------
-- Points
---------------------------------------------------------------------------

local function showTip(p)
    local n = p.node
    if not n then return end
    local t = ns.Tooltip(p, "ANCHOR_RIGHT")
    local c = COLORS[n.fac]
    t:SetText(n.name or "?", c[1], c[2], c[3])
    local what = (n.fac == "alliance" and L.MAP_FLIGHT_ALLIANCE) or (n.fac == "horde" and L.MAP_FLIGHT_HORDE)
        or L.MAP_FLIGHT_NEUTRAL
    t:AddLine(what, 1, 1, 1)
    if n.unknown then t:AddLine(L.MAP_FLIGHT_UNKNOWN, 0.6, 0.6, 0.6) end
    t:Show()
end

local function pinAt(i)
    local p = pins[i]
    if p then return p end
    p = CreateFrame("Frame", nil, layer)
    p:SetSize(SIZE, SIZE)
    -- survol seulement : les clics passent a la carte (zoom, carte suivante)
    p:EnableMouse(true)
    if p.SetMouseClickEnabled then pcall(p.SetMouseClickEnabled, p, false) end
    p.ring = p:CreateTexture(nil, "ARTWORK", nil, 0)
    p.ring:SetAllPoints()
    p.ring:SetTexture(DISC)
    p.ring:SetVertexColor(0, 0, 0, 0.9)
    p.fill = p:CreateTexture(nil, "ARTWORK", nil, 1)
    p.fill:SetPoint("TOPLEFT", 2, -2)
    p.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    p.fill:SetTexture(DISC)
    -- reflet : un point clair en haut a gauche
    p.shine = p:CreateTexture(nil, "ARTWORK", nil, 2)
    p.shine:SetSize(4, 4)
    p.shine:SetPoint("TOPLEFT", 3.5, -3.5)
    p.shine:SetTexture(DISC)
    p.shine:SetVertexColor(1, 1, 1, 0.55)
    p:SetScript("OnEnter", showTip)
    p:SetScript("OnLeave", ns.HideTooltip)
    pins[i] = p
    return p
end

local function hideAll()
    for _, p in ipairs(pins) do p:Hide() end
    for i = #nodes, 1, -1 do nodes[i] = nil end
end

-- points de la carte affichee
local function refresh()
    hideAll()
    local d = mdb()
    if not (d and d.flights and layer) then return end
    local wm = canvas()
    local mapID = mapIDOf(wm)
    if not mapID or not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
    local ok, list = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
    if not ok or type(list) ~= "table" then return end
    local mine = myFaction()
    for _, info in ipairs(list) do
        if type(info) == "table" then
            local x, y = readXY(info.position)
            local fac = factionOf(info.faction)
            if x and (d.flightsOther or fac == mine or fac == "neutral") then
                local name = info.name
                if issecret(name) or type(name) ~= "string" then name = nil end
                local unknown = info.isUndiscovered
                unknown = (not issecret(unknown) and unknown == true) and (fac == mine or fac == "neutral")
                nodes[#nodes + 1] = { x = x, y = y, name = name, fac = fac, unknown = unknown }
            end
        end
    end
    for i, n in ipairs(nodes) do
        local p = pinAt(i)
        p.node = n
        local c = COLORS[n.fac]
        p.fill:SetVertexColor(c[1], c[2], c[3], 1)
        -- pas encore decouvert (notre faction ou les deux) : estompe
        p:SetAlpha(n.unknown and 0.55 or 1)
        p:Show()
    end
    lastScale = nil   -- a replacer
end

-- place des points (taille constante a l ecran, quel que soit le zoom)
local function place(child, s)
    local w, h = child:GetWidth(), child:GetHeight()
    if type(w) ~= "number" or type(h) ~= "number" or issecret(w) or issecret(h) then return end
    local ps = ((mdb() and mdb().flightSize) or 100) / 100 / s
    for i, n in ipairs(nodes) do
        local p = pins[i]
        p:SetScale(ps)
        p:ClearAllPoints()
        -- decalages dans l echelle du point (comme les points du jeu)
        p:SetPoint("CENTER", child, "TOPLEFT", n.x * w / ps, -n.y * h / ps)
    end
    lastScale, lastW, lastH = s, w, h
end

local function onUpdate()
    local wm, sc, child = canvas()
    if not child then return end
    local id = mapIDOf(wm)
    if id ~= lastMap then
        lastMap = id
        refresh()
    end
    if #nodes == 0 then return end
    local s = canvasScale(sc, child)
    if s ~= lastScale or child:GetWidth() ~= lastW or child:GetHeight() ~= lastH then place(child, s) end
end

-- calque pose sur le canevas de la carte (une fois la carte chargee)
local function setup()
    if layer then return true end
    local _, _, child = canvas()
    if not child then return false end
    layer = CreateFrame("Frame", nil, child)
    layer:SetAllPoints(child)
    layer:SetFrameLevel((child:GetFrameLevel() or 1) + 100)
    layer:SetScript("OnUpdate", onUpdate)
    return true
end

-- reglage change : points relus (calque cache si coupe)
function ns.FlightsRefresh()
    if not layer then return end
    local d = mdb()
    layer:SetShown(d and d.flights and true or false)
    lastMap = nil
    refresh()
end

---------------------------------------------------------------------------
-- Diagnostic : /corp minicarte vols
---------------------------------------------------------------------------

function ns.FlightDiag()
    local wm = canvas()
    local mapID = mapIDOf(wm)
    local api = (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) and "ok" or "absente"
    local count = { alliance = 0, horde = 0, neutral = 0 }
    local total, first = 0, nil
    if mapID and api == "ok" then
        local ok, list = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
        if ok and type(list) == "table" then
            for _, info in ipairs(list) do
                total = total + 1
                local fac = factionOf(info.faction)
                count[fac] = count[fac] + 1
                first = first or info
            end
        end
    end
    ns.Say(string.format(L.MAP_FLIGHT_DIAG, tostring(mapID), total, count.alliance, count.horde, count.neutral, api))
    if first then
        local x, y = readXY(first.position)
        ns.Say(string.format("  %s : faction %s, x %s, y %s, inconnu %s", tostring(first.name), tostring(first.faction),
            tostring(x), tostring(y), tostring(first.isUndiscovered)))
    end
    if not layer then ns.Say("  calque absent (carte du monde pas encore chargee)") end
end

---------------------------------------------------------------------------
-- Reglages : section dans le panneau de la minicarte
---------------------------------------------------------------------------

ns.MapOptionsHooks = ns.MapOptionsHooks or {}
table.insert(ns.MapOptionsHooks, function(form)
    form:Gap(4)
    form:Header(L.MAP_H_FLIGHTS)
    form:Columns(2)
    form:Check(L.MAP_OPT_FLIGHTS, function() return mdb() and mdb().flights end, function(v)
        mdb().flights = v
        ns.FlightsRefresh()
    end)
    form:Check(L.MAP_OPT_FLIGHTS_OTHER, function() return mdb() and mdb().flightsOther end, function(v)
        mdb().flightsOther = v
        ns.FlightsRefresh()
    end)
    form:EndColumns()
end)

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, arg)
    if ns.ModuleOff("minicarte", ev) then return end
    if event == "PLAYER_LOGIN" then
        local d = ns.InitRoot().map
        if type(d) ~= "table" then
            ns.root.map = ns.root.map or {}
            d = ns.root.map
        end
        if d.flights == nil then d.flights = true end
        if d.flightsOther == nil then d.flightsOther = true end
        if setup() then ns.FlightsRefresh() end
    elseif event == "ADDON_LOADED" then
        -- carte chargee a la demande sur certains clients
        if arg == "Blizzard_WorldMap" and setup() then ns.FlightsRefresh() end
    elseif event == "TAXI_NODE_STATUS_CHANGED" then
        lastMap = nil
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "TAXI_NODE_STATUS_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
