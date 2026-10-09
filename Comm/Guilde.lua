--[[--------------------------------------------------------------------------
    CorpUI - marque CorpUI dans la liste des membres de la guilde
    (CommunitiesFrame, mode Membres : MemberList en affichage etendu)

    Une vraie colonne dans la liste de Blizzard demanderait de toucher a
    ses colonnes et a ses lignes (taint). A la place, chaque ligne d un
    membre qui a CorpUI recoit, a son extremite droite, une petite plaque a
    nous : lisere, fond sombre (la fin d une note tronquee passe dessous) et
    logo CorpUI. Au survol de la plaque : "CorpUI vX.Y" et l anciennete de
    la derniere annonce. Les clics traversent la plaque (menu et fiche du
    membre de Blizzard intacts).

    Regles de ce client (valeurs secretes, taint) :
      - aucun crochet, aucun SetScript / SetPoint / Show / Hide sur un cadre
        de Blizzard, aucune methode de mixin appelee ;
      - lecture seule des champs de la ligne (memberInfo, isInvitation,
        boutons de voix / faction) ; aucune ecriture chez Blizzard : nos
        plaques sont rangees dans une table faible a nous, indexee par la
        ligne (les lignes sont recyclees par la ScrollBox) ;
      - nos cadres sont enfants des lignes et ancres sur elles ;
      - releve 4 fois par seconde fenetre ouverte (et tout de suite quand
        la liste des CorpUI change), rien en combat.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end
local weak = { __mode = "k" }

local marks = setmetatable({}, weak)    -- ligne de Blizzard -> { f, v, seen, anchor }
local byFrame = setmetatable({}, weak)  -- notre plaque -> sa fiche
local SIZE = 16                         -- plaque : logo de 12 + fond + lisere
local lit = false                       -- au moins une plaque affichee
local dirty = true

local function read(t, k)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[k] end)
    if not ok or issecret(v) then return nil end
    return v
end

-- getter de Blizzard (C) en lecture : nil s il echoue ou si c est secret
local function ask(f, method)
    local m = read(f, method)
    if type(m) ~= "function" then return nil end
    local ok, v = pcall(m, f)
    if not ok or issecret(v) then return nil end
    return v
end

local function visible(f) return ask(f, "IsVisible") == true end
local function shown(f) return ask(f, "IsShown") == true end

local function objType(o)
    local t = ask(o, "GetObjectType")
    if type(t) == "string" then return t end
end

-- ligne de membre (CommunitiesMemberListEntryTemplate)
local function isMemberRow(r)
    return objType(r) == "Button" and type(read(r, "NameFrame")) == "table" and type(read(r, "Note")) == "table"
        and type(read(r, "Level")) == "table"
end

-- nom du membre : champ memberInfo.name (lecture seule) ; ni invitation,
-- ni en-tete de metier, ni communaute Battle.net. Second retour : la
-- ligne est la notre (memberInfo.isSelf)
local function memberName(r)
    if read(r, "isInvitation") == true then return nil end
    local info = read(r, "memberInfo")
    if type(info) ~= "table" then return nil end
    local bnet = Enum and Enum.ClubType and Enum.ClubType.BattleNet
    local ct = read(info, "clubType")
    if bnet ~= nil and ct ~= nil and ct == bnet then return nil end
    local name = read(info, "name")
    if type(name) ~= "string" or name == "" then return nil end
    return name, read(info, "isSelf") == true
end

---------------------------------------------------------------------------
-- Plaque
---------------------------------------------------------------------------

local function tipOn(self)
    local m = byFrame[self]
    if not m or not m.v then return end
    local C = ns.COLORS
    local t = ns.Tooltip(self, "ANCHOR_RIGHT")
    t:AddLine(string.format(L.COMM_TIP, m.v), C.gold[1], C.gold[2], C.gold[3])
    if m.seen and ns.FormatAgo then t:AddLine(ns.FormatAgo(m.seen), 0.7, 0.7, 0.7) end
    t:Show()
end

local function tipOff()
    ns.HideTooltip()
end

local function newMark(row)
    local C = ns.COLORS
    local f = CreateFrame("Frame", nil, row)
    f:SetSize(SIZE, SIZE)
    local edge = f:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(f)
    edge:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    local fill = f:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 1)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    icon:SetTexture(ns.LOGO)
    -- survol seulement : les clics passent a la ligne en dessous
    local motion = pcall(f.SetMouseMotionEnabled, f, true)
    local noClick = motion and pcall(f.SetMouseClickEnabled, f, false)
    if not noClick then
        f:EnableMouse(true)
        pcall(f.SetPropagateMouseClicks, f, true)
    end
    f:SetScript("OnEnter", tipOn)
    f:SetScript("OnLeave", tipOff)
    f:Hide()
    local m = { f = f, icon = icon }
    byFrame[f] = m
    return m
end

-- a droite de la ligne ; a gauche des boutons de voix / faction / annulation
-- quand Blizzard en affiche (ancre a eux, jamais l inverse)
local AVOID = { "SelfMuteButton", "MemberMuteButton", "SelfDeafenButton", "CancelInvitationButton", "FactionButton" }

local function place(m, row)
    local key, rel = "row", row
    for _, k in ipairs(AVOID) do
        local b = read(row, k)
        if type(b) == "table" and shown(b) then
            key, rel = k, b
            break
        end
    end
    if m.anchor == key then return end
    m.anchor = key
    m.f:ClearAllPoints()
    if key == "row" then
        m.f:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    else
        m.f:SetPoint("RIGHT", rel, "LEFT", -3, 0)
    end
end

local function hideAll()
    for _, m in pairs(marks) do
        if m.f:IsShown() then m.f:Hide() end
    end
    lit = false
end

local function update(row)
    local m = marks[row]
    local name, isSelf
    if visible(row) then name, isSelf = memberName(row) end
    local v, seen
    if isSelf and ns.Comm then
        v = ns.Comm.Version()
    elseif name and ns.Comm then
        v, seen = ns.Comm.Lookup(name)
    end
    if not v then
        if m and m.f:IsShown() then m.f:Hide() end
        return
    end
    if not m then
        m = newMark(row)
        marks[row] = m
    end
    m.v, m.seen = v, seen
    place(m, row)
    if not m.f:IsShown() then m.f:Show() end
    lit = true
end

local function scan()
    local cf = _G.CommunitiesFrame
    local ml = read(cf, "MemberList")
    local active = type(ml) == "table" and visible(ml) and read(ml, "expandedDisplay") == true
    if not active then
        if lit then hideAll() end
        return
    end
    local target = read(read(ml, "ScrollBox"), "ScrollTarget")
    if type(target) ~= "table" or type(target.GetChildren) ~= "function" then return end
    local ok, kids = pcall(function() return { target:GetChildren() } end)
    if not ok then return end
    for _, row in ipairs(kids) do
        if isMemberRow(row) then update(row) end
    end
end

local acc = 0
local reported = false   -- une seule erreur signalee par session
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
    acc = acc + (dt or 0)
    if acc < 0.25 and not dirty then return end
    if InCombatLockdown() then return end
    acc, dirty = 0, false
    if not _G.CommunitiesFrame and not lit then return end
    local ok, err = pcall(scan)
    if not ok and not reported then
        reported = true
        geterrorhandler()(err)
    end
end)

if ns.Comm then ns.Comm.Listen(function() dirty = true end) end
