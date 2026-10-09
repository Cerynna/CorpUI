--[[--------------------------------------------------------------------------
    CorpUI - module Minicarte
    Minicarte carree a liseré fin, decorations de Blizzard rangees dans le
    parent cache (anneau, boussole, boutons de zoom, texte de zone), zoom
    a la molette, et sous la carte : zone, coordonnees, heure.
    En plus (facon ElvUI) : taille reglable, retour automatique au zoom 0,
    icones CorpUI (courrier, suivi, difficulte) alimentees par l API, et
    collecteur des boutons d addons (LibDBIcon...) dans une barre CorpUI.

    On ne deplace pas la minicarte (elle reste geree par le mode Edition de
    Blizzard) : on change seulement son masque et ce qui l entoure.
    GetMinimapShape (convention des addons pour placer leurs boutons) est
    defini seulement s il n existe pas deja.
    Aucun cadre de Blizzard n est deplace ni accroche : leurs icones sont
    seulement rangees dans le parent cache (ns.HideBlizzard), les notres
    lisent l API.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local DECO = {
    "MinimapCluster.BorderTop", "MinimapCompassTexture", "MinimapBackdrop",
    "Minimap.ZoomIn", "Minimap.ZoomOut", "Minimap.ZoomHitArea",
    "MinimapCluster.ZoneTextButton", "MinimapZoneTextButton",
    "MinimapBorder", "MinimapBorderTop", "MinimapZoomIn", "MinimapZoomOut",
    "MinimapToggleButton", "MiniMapWorldMapButton",
    "TimeManagerClockButton",      -- remplacee par l heure du bandeau
    "GameTimeFrame",               -- soleil/lune du calendrier, incruste dans le coin
    -- soleil / lune du cycle jour-nuit propre a ce client (Camelot :
    -- Blizzard_Minimap/Camelot/Diel.lua), cadre sans nom ni souris pose
    -- au-dessus de la carte, au centre de MinimapCluster decale de (63, 72)
    "MinimapCluster.DielFrame",
}
-- icones de Blizzard remplacees par les notres (cachees seulement si la
-- notre est active ET si "masquer les decorations" est coche)
local BLIZZ_MAIL = { "MinimapCluster.IndicatorFrame" }       -- courrier (+ commandes d artisanat)
local BLIZZ_TRACK = { "MinimapCluster.Tracking" }
local BLIZZ_DIFF = { "MinimapCluster.InstanceDifficulty" }
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
local ROUND_MASK = "Textures\\MinimapMask"

local issecret = issecretvalue or function() return false end

local db
local border, info, zoneText, coordText, clockText
local definedShape = false
local layoutIcons, layoutBar      -- definies plus bas

---------------------------------------------------------------------------
-- Infos sous la carte
---------------------------------------------------------------------------

local PVP_COLORS = {
    sanctuary = { 0.41, 0.8, 0.94 }, friendly = { 0.1, 1, 0.1 }, hostile = { 1, 0.1, 0.1 },
    contested = { 1, 0.7, 0 }, combat = { 1, 0.1, 0.1 }, arena = { 1, 0.1, 0.1 },
}

local function updateInfo()
    if not info or not info:IsShown() then return end
    local zone = GetMinimapZoneText and GetMinimapZoneText() or ""
    zoneText:SetText(zone)
    local pvp = GetZonePVPInfo and GetZonePVPInfo()
    local c = PVP_COLORS[pvp or ""] or { 1, 0.82, 0 }
    zoneText:SetTextColor(c[1], c[2], c[3])
    local coords = ""
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, x, y = pcall(function()
            local map = C_Map.GetBestMapForUnit("player")
            local pos = map and C_Map.GetPlayerMapPosition(map, "player")
            if pos then return pos:GetXY() end
        end)
        if ok and x and y then coords = string.format("%.1f, %.1f", x * 100, y * 100) end
    end
    coordText:SetText(db.coords and coords or "")
    clockText:SetText(db.clock and date("%H:%M") or "")
end

---------------------------------------------------------------------------
-- Zoom : la molette est geree par Blizzard sur ce client (MinimapMixin,
-- script OnMouseWheel) ; on ne la remplace pas. Retour au zoom 0 apres
-- db.zoomReset secondes (0 = jamais), suivi par MINIMAP_UPDATE_ZOOM.
---------------------------------------------------------------------------

local zoomToken = 0

-- remet les boutons de zoom de Blizzard (caches) dans un etat coherent :
-- la molette de Blizzard passe par leurs clics, un bouton desactive la bloquerait
local function syncZoomButtons()
    local ok, z, levels = pcall(function() return Minimap:GetZoom(), Minimap:GetZoomLevels() end)
    if not ok or type(z) ~= "number" or type(levels) ~= "number" then return end
    local zi, zo = Minimap.ZoomIn, Minimap.ZoomOut
    if type(zi) == "table" and zi.SetEnabled then pcall(zi.SetEnabled, zi, z < levels - 1) end
    if type(zo) == "table" and zo.SetEnabled then pcall(zo.SetEnabled, zo, z > 0) end
end

local function scheduleZoomReset()
    zoomToken = zoomToken + 1
    local delay = (db and db.enabled and db.zoomReset) or 0
    if delay <= 0 then return end
    local ok, z = pcall(Minimap.GetZoom, Minimap)
    if not ok or not z or z == 0 then return end
    local token = zoomToken
    C_Timer.After(delay, function()
        if token ~= zoomToken then return end
        -- souris sur la carte : on attend encore un tour
        if Minimap:IsMouseOver() then scheduleZoomReset() return end
        pcall(Minimap.SetZoom, Minimap, 0)
        syncZoomButtons()
    end)
end

-- apres un changement de taille, le rendu de la carte doit etre relance
local function refreshZoom()
    local ok, z, levels = pcall(function() return Minimap:GetZoom(), Minimap:GetZoomLevels() end)
    if not ok or type(z) ~= "number" or type(levels) ~= "number" or levels < 2 then return end
    pcall(Minimap.SetZoom, Minimap, z > 0 and z - 1 or z + 1)
    pcall(Minimap.SetZoom, Minimap, z)
end

---------------------------------------------------------------------------
-- Taille de la carte : Minimap n est pas un cadre "systeme" du mode Edition
-- (seul son bloc MinimapCluster l est, avec son echelle). Sa taille se
-- change donc sans conflit ; l echelle du bloc reste celle du mode Edition.
---------------------------------------------------------------------------

local origW, origH

local function applySize(on)
    if InCombatLockdown() then return end
    if not origW then origW, origH = Minimap:GetWidth(), Minimap:GetHeight() end
    local w, h = origW, origH
    if on and db.size then w, h = db.size, db.size end
    if math.abs((Minimap:GetWidth() or 0) - w) < 0.5 and math.abs((Minimap:GetHeight() or 0) - h) < 0.5 then return end
    Minimap:SetSize(w, h)
    refreshZoom()
end

---------------------------------------------------------------------------
-- Icones CorpUI : difficulte, suivi, courrier. Dans le bandeau (centre du
-- bas) s il est affiche, sinon dans le coin haut-droit de la carte.
---------------------------------------------------------------------------

local iconBar, diffBtn, trackBtn, mailBtn

local function iconButton()
    local b = CreateFrame("Button", nil, iconBar)
    b:SetSize(16, 16)
    ns.UI.Skin(b, 0.85)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(ns.COLORS.violet[1], ns.COLORS.violet[2], ns.COLORS.violet[3], 0.3)
    b:SetScript("OnLeave", ns.HideTooltip)
    b:Hide()
    return b
end

local function setAtlasOr(tex, atlas, file)
    local ok = pcall(tex.SetAtlas, tex, atlas)
    local okA, got = pcall(tex.GetAtlas, tex)
    if not ok or (okA and not got) then
        tex:SetTexture(file)
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

-- difficulte d instance : nombre de joueurs (+ H si heroique), dans une instance
local function updateDiff()
    local want, label = false, ""
    local ok, name, itype, diffID, diffName, maxPlayers = pcall(GetInstanceInfo)
    if ok and itype and itype ~= "none" then
        local heroic = false
        if GetDifficultyInfo and diffID then
            local ok2, _, _, isHeroic, _, displayHeroic = pcall(GetDifficultyInfo, diffID)
            heroic = ok2 and (isHeroic or displayHeroic) and true or false
        end
        local n = tonumber(maxPlayers) or 0
        label = (n > 0 and tostring(n) or "") .. (heroic and "H" or "")
        want = label ~= ""
        diffBtn.tipTitle, diffBtn.tipText = name, diffName
    end
    diffBtn.text:SetText(label)
    diffBtn.want = want
end

-- suivi : icone du suivi de sort actif (herbes, minerais...), sinon loupe
local function trackingList()
    local list = {}
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return list end
    local optional = MinimapConstants and MinimapConstants.OPTIONAL_FILTERS
    for i = 1, C_Minimap.GetNumTrackingTypes() or 0 do
        local t = C_Minimap.GetTrackingInfo(i)
        if t then
            local filter = C_Minimap.GetTrackingFilter and C_Minimap.GetTrackingFilter(i)
            -- memes entrees que le menu de Blizzard (sorts + suivis optionnels)
            local shown = not filter or filter.spellID or (optional and filter.filterID and optional[filter.filterID])
            if shown then
                table.insert(list, { index = i, name = t.name, texture = t.texture, active = t.active, spell = t.type == "spell" })
            end
        end
    end
    return list
end

local function updateTrack()
    local tex
    local ok, list = pcall(trackingList)
    if ok then
        for _, t in ipairs(list) do
            if t.active and t.spell and t.texture then tex = t.texture break end
        end
    end
    if tex then
        trackBtn.icon:SetTexture(tex)
        trackBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        setAtlasOr(trackBtn.icon, "ui-hud-minimap-tracking-up", "Interface\\Minimap\\Tracking\\None")
    end
    trackBtn.want = C_Minimap ~= nil and C_Minimap.GetNumTrackingTypes ~= nil
end

local function updateMail()
    local ok, has = pcall(function() return HasNewMail and HasNewMail() end)
    mailBtn.want = ok and has and true or false
end

-- menu de suivi CorpUI (le menu de Blizzard n est pas ouvert par l addon)
local trackMenu
local function openTrackMenu(owner)
    if not trackMenu then
        trackMenu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        trackMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        trackMenu:SetClampedToScreen(true)
        ns.UI.SetBackdrop(trackMenu, 0.98)
        trackMenu.rows = {}
        pcall(trackMenu.RegisterEvent, trackMenu, "GLOBAL_MOUSE_DOWN")
        trackMenu:SetScript("OnEvent", function(self)
            if self:IsShown() and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
                self:Hide()
            end
        end)
        trackMenu:Hide()
    end
    if trackMenu:IsShown() then trackMenu:Hide() return end
    local ok, list = pcall(trackingList)
    if not ok or #list == 0 then ns.Say(L.MAP_TRACK_NONE) return end
    trackMenu.owner = owner
    local C = ns.COLORS
    for i, t in ipairs(list) do
        local row = trackMenu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, trackMenu)
            row:SetHeight(20)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", 6, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.text:SetPoint("RIGHT", -6, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            ns.UI.Gradient(hl, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.4, C.violet[1], C.violet[2], C.violet[3], 0.05)
            trackMenu.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", trackMenu, "TOPLEFT", 1, -1 - (i - 1) * 20)
        row:SetPoint("TOPRIGHT", trackMenu, "TOPRIGHT", -1, -1 - (i - 1) * 20)
        row.icon:SetTexture(t.texture)
        row.text:SetText(t.name or "?")
        if t.active then row.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) else row.text:SetTextColor(1, 1, 1) end
        row:SetScript("OnClick", function()
            trackMenu:Hide()
            pcall(C_Minimap.SetTracking, t.index, not t.active)
            C_Timer.After(0.3, function() pcall(updateTrack) end)
        end)
        row:Show()
    end
    for i = #list + 1, #trackMenu.rows do trackMenu.rows[i]:Hide() end
    trackMenu:SetSize(200, #list * 20 + 2)
    trackMenu:ClearAllPoints()
    trackMenu:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", 0, -2)
    trackMenu:Show()
end

local function buildIcons()
    iconBar = CreateFrame("Frame", nil, Minimap)
    iconBar:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    iconBar:SetSize(16, 16)

    diffBtn = iconButton()
    diffBtn.icon:SetColorTexture(0, 0, 0, 0)
    diffBtn.text = diffBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    diffBtn.text:SetPoint("CENTER", 0, 0)
    diffBtn:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_BOTTOMLEFT")
        t:AddLine(self.tipTitle or L.MAP_OPT_DIFF)
        if self.tipText and self.tipText ~= "" then t:AddLine(self.tipText, 1, 1, 1) end
        t:Show()
    end)

    trackBtn = iconButton()
    trackBtn:RegisterForClicks("LeftButtonUp")
    trackBtn:SetScript("OnClick", function(self) openTrackMenu(self) end)
    trackBtn:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_BOTTOMLEFT")
        t:AddLine(L.MAP_OPT_TRACK)
        local ok, list = pcall(trackingList)
        local any = false
        if ok then
            for _, e in ipairs(list) do
                if e.active then t:AddLine(e.name, 1, 1, 1) any = true end
            end
        end
        if not any then t:AddLine(L.MAP_TRACK_NONE, 0.6, 0.6, 0.6) end
        t:AddLine(L.MAP_TRACK_CLICK, 0.6, 0.6, 0.6)
        t:Show()
    end)

    mailBtn = iconButton()
    setAtlasOr(mailBtn.icon, "ui-hud-minimap-mail-up", "Interface\\Minimap\\Tracking\\Mailbox")
    mailBtn:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_BOTTOMLEFT")
        t:AddLine(L.MAP_MAIL_NEW)
        local ok, a, b, c = pcall(function() if GetLatestThreeSenders then return GetLatestThreeSenders() end end)
        if ok then
            for _, s in ipairs({ a, b, c }) do
                if type(s) == "string" and not issecret(s) then t:AddLine(s, 1, 1, 1) end
            end
        end
        t:Show()
    end)
end

layoutIcons = function()
    if not iconBar then return end
    local on = db.enabled
    local inStrip = info and info:IsShown()
    local size = inStrip and 14 or 18
    local list = {}
    for _, e in ipairs({ { diffBtn, "iconDiff" }, { trackBtn, "iconTrack" }, { mailBtn, "iconMail" } }) do
        local b, key = e[1], e[2]
        if on and db[key] and b.want then
            table.insert(list, b)
        else
            b:Hide()
        end
    end
    local x = 0
    for _, b in ipairs(list) do
        local w = size
        if b == diffBtn then w = math.max(size, (b.text:GetStringWidth() or 0) + 6) end
        b:SetSize(w, size)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", iconBar, "TOPLEFT", x, 0)
        b:Show()
        x = x + w + 2
    end
    iconBar:SetSize(math.max(1, x - 2), size)
    iconBar:ClearAllPoints()
    if inStrip then
        iconBar:SetPoint("BOTTOM", info, "BOTTOM", 0, 2)
    else
        iconBar:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -3, -3)
    end
    iconBar:SetShown(#list > 0)
end

local function updateIcons()
    if not iconBar then return end
    pcall(updateDiff)
    pcall(updateTrack)
    pcall(updateMail)
    layoutIcons()
end

---------------------------------------------------------------------------
-- Collecteur de boutons d addons
-- Boutons d AUTRES addons accroches a Minimap, MinimapBackdrop ou
-- MinimapCluster (LibDBIcon10_*, et boutons nommes non Blizzard). Ils sont
-- re-parentes dans notre barre, chacun centre dans une case CorpUI. Leur
-- etat d origine est garde pour tout remettre si le collecteur est coupe.
-- Les cadres de Blizzard sont exclus : nom global ecrit par du code
-- securise (issecurevariable), ou cadre protege.
---------------------------------------------------------------------------

-- noms ignores (epingles de carte de GatherMate, HandyNotes, TomTom...)
local IGNORE = { "Pin", "Node", "Note", "POI", "Arrow", "HereBeDragons", "GatherMate", "HandyNotes", "TomTom", "Ping" }
-- textures rondes de LibDBIcon (bordure de suivi, fond) : cachees dans la barre
local ROUND_TEX = { [136430] = true, [136467] = true }

local bar, toggleBtn
local slots = {}
local collected = {}     -- bouton -> etat d origine
local drawerOpen = false

local function isBlizzardName(name)
    if not issecurevariable then return true end   -- par prudence : seulement LibDBIcon
    local ok, secure = pcall(issecurevariable, name)
    return not ok or secure and true or false
end

local function collectable(f)
    if f == bar or f == iconBar or f == toggleBtn or f == info or f == border then return false end
    local okN, name = pcall(f.GetName, f)
    if not okN or type(name) ~= "string" or issecret(name) then return false end
    if f.IsForbidden and f:IsForbidden() then return false end
    if f.IsProtected and f:IsProtected() then return false end
    if name:find("^LibDBIcon10_") or name == "CorpUIMinimapButton" then return true end
    if isBlizzardName(name) then return false end
    local okT, kind = pcall(f.GetObjectType, f)
    if not okT or kind ~= "Button" then return false end
    for _, p in ipairs(IGNORE) do
        if name:find(p) then return false end
    end
    local w, h = f:GetWidth(), f:GetHeight()
    if not w or not h or w < 12 or w > 48 or h < 12 or h > 48 then return false end
    return f:GetScript("OnClick") ~= nil or f:GetScript("OnMouseUp") ~= nil
end

local function isRoundDeco(r)
    if not r.GetObjectType or r:GetObjectType() ~= "Texture" then return false end
    local ok, t = pcall(r.GetTexture, r)
    if not ok or t == nil or issecret(t) then return false end
    if type(t) == "number" then return ROUND_TEX[t] or false end
    if type(t) == "string" then
        local s = t:lower()
        return s:find("trackingborder") ~= nil or s:find("ui%-minimap%-background") ~= nil
    end
    return false
end

local function grab(f)
    local s = {
        parent = f:GetParent(), points = {}, scale = f:GetScale() or 1,
        strata = f:GetFrameStrata(), level = f:GetFrameLevel(), alphas = {},
        drag = f:GetScript("OnDragStart") ~= nil,
    }
    for i = 1, (f:GetNumPoints() or 0) do s.points[i] = { f:GetPoint(i) } end
    for _, r in ipairs({ f:GetRegions() }) do
        if isRoundDeco(r) then
            s.alphas[r] = r:GetAlpha() or 1
            r:SetAlpha(0)
        end
    end
    -- plus de glisser autour de la carte tant qu il est dans la barre
    if s.drag then pcall(f.RegisterForDrag, f) end
    collected[f] = s
end

local function release(f)
    local s = collected[f]
    if not s then return end
    collected[f] = nil
    pcall(f.SetParent, f, s.parent)
    pcall(f.SetScale, f, s.scale)
    if s.strata then pcall(f.SetFrameStrata, f, s.strata) end
    if s.level then pcall(f.SetFrameLevel, f, s.level) end
    f:ClearAllPoints()
    for _, p in ipairs(s.points) do pcall(f.SetPoint, f, unpack(p)) end
    for r, a in pairs(s.alphas) do pcall(r.SetAlpha, r, a) end
    if s.drag then pcall(f.RegisterForDrag, f, "LeftButton") end
end

local function releaseAll()
    for f in pairs(collected) do release(f) end
end

local function scanButtons()
    local found = false
    for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
        if type(parent) == "table" and parent.GetChildren then
            for _, f in ipairs({ parent:GetChildren() }) do
                if not collected[f] then
                    local ok, yes = pcall(collectable, f)
                    if ok and yes and pcall(grab, f) then found = true end
                end
            end
        end
    end
    return found
end

local function newSlot(i)
    local s = CreateFrame("Frame", nil, bar)
    s:SetFrameLevel(bar:GetFrameLevel() + 1)
    ns.UI.Skin(s, 0.6)
    slots[i] = s
    return s
end

-- echelle pour que l icone remplisse la case (LibDBIcon : icone de ~18 px
-- au milieu d un bouton de 31 px dont la bordure ronde est cachee)
local function fitScale(f, size)
    local w, h = f:GetWidth() or size, f:GetHeight() or size
    local ref = math.max(w, h)
    local icon = rawget(f, "icon")
    if type(icon) == "table" and icon.GetWidth then
        local iw = icon:GetWidth()
        if type(iw) == "number" and iw > 4 and iw < ref then ref = iw + 2 end
    end
    if ref <= 0 then return 1 end
    return math.max(0.3, math.min(2, (size - 2) / ref))
end

local function place(f, slot, size)
    local s = collected[f]
    s.slot = slot
    if f:GetParent() ~= bar then pcall(f.SetParent, f, bar) end
    pcall(f.SetFrameStrata, f, bar:GetFrameStrata())
    pcall(f.SetFrameLevel, f, slot:GetFrameLevel() + 2)
    pcall(f.SetScale, f, fitScale(f, size))
    f:ClearAllPoints()
    f:SetPoint("CENTER", slot, "CENTER", 0, 0)
    f:SetAlpha(1)
end

local function shownList()
    local list = {}
    for f in pairs(collected) do
        if f:IsShown() then table.insert(list, f) end
    end
    table.sort(list, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
    return list
end

layoutBar = function()
    if not bar then return end
    local list = shownList()
    local on = db.enabled and db.collect and #list > 0
    local size, gap, pad = db.btnSize or 22, 3, 3
    local width = Minimap:GetWidth() or 198
    local per = math.max(1, math.floor((width - 2 * pad + gap) / (size + gap)))
    local rows = math.max(1, math.ceil(#list / per))
    local anchor = (info and info:IsShown()) and info or Minimap
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
    bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -3)
    bar:SetHeight(rows * (size + gap) - gap + 2 * pad)
    for i, f in ipairs(list) do
        local slot = slots[i] or newSlot(i)
        slot:SetSize(size, size)
        slot:ClearAllPoints()
        local r, c = math.floor((i - 1) / per), (i - 1) % per
        slot:SetPoint("TOPLEFT", bar, "TOPLEFT", pad + c * (size + gap), -pad - r * (size + gap))
        slot:Show()
        local ok, err = pcall(place, f, slot, size)
        if not ok then geterrorhandler()(err) end
    end
    for i = #list + 1, #slots do slots[i]:Hide() end
    -- boutons caches par leur addon : plus de case
    for f, s in pairs(collected) do
        if not f:IsShown() then s.slot = nil end
    end
    local drawer = db.collectMode == "drawer"
    toggleBtn:SetShown(on and drawer)
    toggleBtn.text:SetText(drawerOpen and "-" or "+")
    bar:SetShown(on and (not drawer or drawerOpen))
end

-- un bouton a ete remis ailleurs par son addon (LibDBIcon le replace sur
-- la carte quand il se montre ou se rafraichit), ou vient d apparaitre
local function misplaced()
    for f, s in pairs(collected) do
        if f:IsShown() then
            if not s.slot or f:GetParent() ~= bar or (f:GetNumPoints() or 0) ~= 1 then return true end
            local _, rel = f:GetPoint(1)
            if rel ~= s.slot then return true end
        elseif s.slot then
            return true
        end
    end
    return false
end

local function collectorTick()
    if not bar then return end
    if not (db.enabled and db.collect) then
        if next(collected) then releaseAll() end
        layoutBar()
        return
    end
    local found = scanButtons()
    if found or misplaced() then layoutBar() end
end

local function buildCollector()
    bar = CreateFrame("Frame", nil, Minimap)
    bar:SetFrameLevel(Minimap:GetFrameLevel() + 4)
    ns.UI.Skin(bar, 0.9)
    bar:Hide()

    -- tiroir : petit bouton dans le coin bas-droit de la carte
    toggleBtn = CreateFrame("Button", nil, Minimap)
    toggleBtn:SetSize(16, 16)
    toggleBtn:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    toggleBtn:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -3, 3)
    ns.UI.Skin(toggleBtn, 0.9)
    toggleBtn.text = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toggleBtn.text:SetPoint("CENTER", 1, 0)
    local hl = toggleBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(ns.COLORS.violet[1], ns.COLORS.violet[2], ns.COLORS.violet[3], 0.3)
    toggleBtn:SetScript("OnClick", function()
        drawerOpen = not drawerOpen
        layoutBar()
    end)
    toggleBtn:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_BOTTOMLEFT")
        t:AddLine(string.format(L.MAP_DRAWER_TIP, #shownList()))
        t:Show()
    end)
    toggleBtn:SetScript("OnLeave", ns.HideTooltip)
    toggleBtn:Hide()
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function build()
    -- liseré : quatre traits autour de la carte
    border = CreateFrame("Frame", nil, Minimap)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    local function line(p1, p2, w, h)
        local t = border:CreateTexture(nil, "OVERLAY")
        local c = ns.COLORS.border
        t:SetColorTexture(c[1], c[2], c[3], 1)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    line("TOPLEFT", "TOPRIGHT", nil, 1)
    line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    line("TOPLEFT", "BOTTOMLEFT", 1, nil)
    line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

    info = CreateFrame("Frame", nil, Minimap)
    info:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", 0, -3)
    info:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -3)
    info:SetHeight(32)
    ns.UI.Skin(info, 0.9)
    zoneText = info:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zoneText:SetPoint("TOPLEFT", 4, -3)
    zoneText:SetPoint("TOPRIGHT", -4, -3)
    zoneText:SetWordWrap(false)
    coordText = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coordText:SetPoint("BOTTOMLEFT", 4, 3)
    clockText = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clockText:SetPoint("BOTTOMRIGHT", -4, 3)
    local elapsed = 1
    info:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end
        elapsed = 0
        updateInfo()
    end)

    -- La minicarte appartient au mode Edition de Blizzard, qui la replace a sa
    -- facon : la deplacer par addon ne tient pas (constate le 04/10/2026) et
    -- risque de perturber le mode Edition. Au deverrouillage, une simple
    -- etiquette renvoie vers le mode Edition ; carre, liseré et bandeau
    -- suivent la carte tout seuls.
    local note = CreateFrame("Frame", nil, Minimap)
    note:SetAllPoints()
    note:SetFrameStrata("DIALOG")
    local t = note:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetColorTexture(ns.COLORS.violet[1], ns.COLORS.violet[2], ns.COLORS.violet[3], 0.3)
    local fs = note:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 6, 0)
    fs:SetPoint("RIGHT", -6, 0)
    fs:SetText(L.MAP_EDITMODE)
    note:SetShown(ns.moversShown)
    table.insert(ns.movers, note)

    -- zoom a la molette : celui du jeu clique ses boutons +/-, ranges dans
    -- le parent cache, donc sans effet. Une couche a nous, qui ne prend que
    -- la molette (les clics et le survol passent a la carte), zoome elle-meme.
    local wheel = CreateFrame("Frame", nil, Minimap)
    wheel:SetAllPoints(Minimap)
    wheel:SetFrameLevel(Minimap:GetFrameLevel() + 1)
    wheel:EnableMouse(false)
    wheel:EnableMouseWheel(true)
    wheel:SetScript("OnMouseWheel", function(_, delta)
        local ok, z, levels = pcall(function() return Minimap:GetZoom(), Minimap:GetZoomLevels() end)
        if not ok then return end
        z = z + (delta > 0 and 1 or -1)
        if z >= 0 and z < levels then
            pcall(Minimap.SetZoom, Minimap, z)
            scheduleZoomReset()
        end
    end)

    buildIcons()
    buildCollector()
end

-- Ce client affiche lui-meme des coordonnees sous la minicarte, dans un cadre
-- dont on ne connait pas le nom. On cherche autour de la carte tout texte au
-- format "12.3, 45.6" (sauf le notre), on le rend transparent, et on note ou
-- il etait (db.gameCoords) pour pouvoir le cibler par son nom plus tard.
local hiddenCoords = {}
local function hideGameCoords(hide)
    for _, r in ipairs(hiddenCoords) do pcall(r.SetAlpha, r, hide and 0 or 1) end
    if not hide then return end
    local found = {}
    local function scan(f, path, depth)
        if not f or depth > 5 or f == info or f == border or f == bar or f == iconBar then return end
        for _, r in ipairs({ f:GetRegions() }) do
            if r ~= coordText and r ~= zoneText and r ~= clockText
                and r.GetObjectType and r:GetObjectType() == "FontString" then
                local ok, t = pcall(r.GetText, r)
                if ok and type(t) == "string" and not issecret(t)
                    and t:match("^%s*%d+%.?%d*%s*,%s*%d+%.?%d*%s*$") then
                    pcall(r.SetAlpha, r, 0)
                    table.insert(hiddenCoords, r)
                    table.insert(found, path)
                end
            end
        end
        for i, c in ipairs({ f:GetChildren() }) do
            -- boutons d addons ranges dans la barre : pas a nous de les fouiller
            if not collected[c] then
                scan(c, path .. "." .. (c:GetName() or ("#" .. i)), depth + 1)
            end
        end
    end
    scan(MinimapCluster, "MinimapCluster", 0)
    scan(Minimap, "Minimap", 0)
    if #found > 0 then db.gameCoords = found end
end

-- Dans son bloc, la carte laisse en haut la place du bandeau de zone de
-- Blizzard (masque) : on l accroche au coin haut-droit du bloc. Le bloc lui
-- reste a la main du mode Edition (la carte suit s il est deplace).
local CORNER_GAP = 4
local function placeInCorner(on)
    if InCombatLockdown() then return end
    if on then
        local p, rel = Minimap:GetPoint(1)
        if p == "TOPRIGHT" and rel == MinimapCluster then return end
        Minimap:ClearAllPoints()
        Minimap:SetPoint("TOPRIGHT", MinimapCluster, "TOPRIGHT", -CORNER_GAP, -CORNER_GAP)
    elseif MinimapCluster.MinimapContainer then
        local _, rel = Minimap:GetPoint(1)
        if rel ~= MinimapCluster then return end
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", MinimapCluster.MinimapContainer, "CENTER", 0, 0)   -- accroche d origine
    end
end

local function apply()
    if InCombatLockdown() then return end
    local on = db.enabled
    placeInCorner(on and db.corner)
    applySize(on)
    pcall(Minimap.SetMaskTexture, Minimap, on and SQUARE_MASK or ROUND_MASK)
    border:SetShown(on)
    info:SetShown(on and db.info)
    local hideB = on and db.hideBlizzard
    ns.HideBlizzard(DECO, hideB)
    ns.HideBlizzard(BLIZZ_MAIL, hideB and db.iconMail)
    ns.HideBlizzard(BLIZZ_TRACK, hideB and db.iconTrack)
    ns.HideBlizzard(BLIZZ_DIFF, hideB and db.iconDiff)
    hideGameCoords(hideB)
    if on and not GetMinimapShape then
        GetMinimapShape = function() return "SQUARE" end
        definedShape = true
    elseif not on and definedShape then
        GetMinimapShape = nil
        definedShape = false
    end
    updateInfo()
    updateIcons()
    collectorTick()
    layoutBar()
    scheduleZoomReset()
end

---------------------------------------------------------------------------
-- Fenetre d options
---------------------------------------------------------------------------

local win

local function buildWindow()
    win = ns.UI.Window("CorpUIMinimapOptions", ns.TITLE .. " - " .. L.MOD_MAP, nil, 440, 200)
    -- en combat : rien ne change (la case est relue et revient a sa valeur)
    local form = ns.UI.Form(win, -34, function()
        if not InCombatLockdown() then apply() end
    end)
    local function blocked()
        if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return true end
    end
    local function check(key, text)
        form:Check(text, function() return db[key] end, function(v)
            if blocked() then return end
            db[key] = v
        end)
    end
    check("enabled", L.MAP_OPT_ENABLE)
    check("hideBlizzard", L.MAP_OPT_BLIZZ)
    check("corner", L.MAP_OPT_CORNER)
    -- bandeau sous la carte et ce qu il montre (libelles courts : 2 colonnes)
    form:Gap(4)
    check("info", L.MAP_OPT_INFO)
    form:Columns(2)
    check("coords", L.MAP_OPT_COORDS)
    check("clock", L.MAP_OPT_CLOCK)
    form:EndColumns()

    -- carte : taille et zoom
    form:Gap(6)
    form:Header(L.MAP_H_MAP)
    form:Columns(2)
    form:Number(L.MAP_OPT_SIZE, function()
        return db.size or math.floor((origW or Minimap:GetWidth() or 198) + 0.5)
    end, function(v)
        if blocked() then return end
        db.size = v
    end, 120, 320, 2)
    form:Number(L.MAP_OPT_ZOOMRESET, function() return db.zoomReset or 0 end, function(v)
        db.zoomReset = v
    end, 0, 30, 1)
    form:EndColumns()

    -- icones CorpUI
    form:Header(L.MAP_H_ICONS)
    form:Columns(2)
    check("iconMail", L.MAP_OPT_MAIL)
    check("iconTrack", L.MAP_OPT_TRACK)
    check("iconDiff", L.MAP_OPT_DIFF)
    form:EndColumns()

    -- boutons des addons
    form:Gap(4)
    form:Header(L.MAP_H_BUTTONS)
    check("collect", L.MAP_OPT_COLLECT)
    form:Columns(2)
    form:Cycle(L.MAP_OPT_MODE, { "bar", "drawer" }, { bar = L.MAP_MODE_BAR, drawer = L.MAP_MODE_DRAWER },
        function() return db.collectMode end, function(v) db.collectMode = v end)
    form:Number(L.MAP_OPT_BTNSIZE, function() return db.btnSize or 22 end, function(v)
        db.btnSize = v
    end, 14, 36, 1)
    form:EndColumns()

    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 8)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.MAP_EDITMODE .. "\n" .. L.MAP_SIZE_NOTE)
    win:SetHeight(-form.y + 50)
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------

local DEFAULTS = {
    enabled = true, hideBlizzard = true, info = true, coords = true, clock = true, corner = true,
    -- ajouts du 05/10 (zoom, icones, collecteur) ; size = nil : taille de Blizzard
    zoomReset = 0, iconMail = true, iconTrack = true, iconDiff = true,
    collect = true, collectMode = "bar", btnSize = 22,
}

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGIN" or db then return end   -- une seule construction
    local root = ns.InitRoot()
    root.map = root.map or {}
    db = root.map
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    -- ancienne tentative de deplacement par addon : abandonnee
    db.placed, db.pos = nil, nil
    build()
    apply()

    -- evenements des icones, du zoom et des addons charges plus tard
    local watch = CreateFrame("Frame")
    watch:SetScript("OnEvent", function(_, event)
        if event == "MINIMAP_UPDATE_ZOOM" then
            scheduleZoomReset()
        elseif event == "ADDON_LOADED" then
            C_Timer.After(1, collectorTick)
        else
            updateIcons()
        end
    end)
    for _, e in ipairs({ "MINIMAP_UPDATE_ZOOM", "MINIMAP_UPDATE_TRACKING", "UPDATE_PENDING_MAIL",
        "PLAYER_ENTERING_WORLD", "PLAYER_DIFFICULTY_CHANGED", "UPDATE_INSTANCE_INFO",
        "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "ADDON_LOADED" }) do
        pcall(watch.RegisterEvent, watch, e)
    end

    local since = 0
    ev:SetScript("OnUpdate", function(_, dt)
        since = since + dt
        if since < 2 then return end
        since = 0
        if db.enabled and db.corner then placeInCorner(true) end
        -- releve periodique : nouveaux boutons, boutons replaces par leur addon
        local ok, err = pcall(collectorTick)
        if not ok then geterrorhandler()(err) end
    end)
    C_Timer.After(3, function() if db.enabled and db.hideBlizzard then hideGameCoords(true) end end)
    C_Timer.After(10, function() if db.enabled and db.hideBlizzard then hideGameCoords(true) end end)
end)
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")

ns.RegisterModule({
    command = "minicarte",
    panelName = "CorpUIMinimapOptions",
    icon = "Interface\\Icons\\INV_Misc_Map02",
    title = function() return L.MOD_MAP end,
    desc = function() return L.MAP_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})
