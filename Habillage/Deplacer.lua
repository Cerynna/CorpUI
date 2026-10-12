--[[--------------------------------------------------------------------------
    CorpUI - fenetres deplacables (module Habillage)
    Les fenetres de Blizzard habillees (liste de Fenetres.lua, sauf les
    popups et les fenetres sans bandeau) se deplacent en tirant le haut de
    leur cadre ; la place est retenue (CorpUIDB.skins.winPos, suit les
    profils) et remise a chaque ouverture. Clic droit sur ce haut : la
    fenetre reprendra la place du jeu a sa prochaine ouverture.

    Rien de Blizzard n est remplace ni accroche : une poignee a nous (cadre
    enfant invisible, sur les 24 px du haut, la croix et les boutons de
    droite laisses libres) appelle StartMoving / SetPoint de la fenetre
    elle-meme. Le gestionnaire des fenetres du jeu la replace a l ouverture
    ou quand une voisine s ouvre : la poignee la remet a sa place des
    qu elle bouge. Fenetre protegee (boutons securises dedans) : rien en
    combat. Carte du monde agrandie : rien.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local TITLE_H = 24         -- hauteur de la zone a tirer
local RIGHT_FREE = 64      -- croix et boutons de la barre de titre
local db                   -- CorpUIDB.skins
local handles = {}         -- fenetre -> poignee

local function blocked(f)
    local okM, maxi = pcall(function() return f.IsMaximized and f:IsMaximized() end)
    if okM and maxi then return true end
    if not InCombatLockdown() then return false end
    local ok, p = pcall(f.IsProtected, f)
    return ok and p and true or false
end

-- place retenue : coin haut-gauche, en unites d UIParent
local function save(f, name)
    local l, t = f:GetLeft(), f:GetTop()
    if not l or not t then return end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    db.winPos[name] = { x = math.floor(l * k + 0.5), y = math.floor(t * k + 0.5) }
end

local function place(f, name)
    local p = db and db.move and db.winPos[name]
    if not p or blocked(f) then return end
    local k = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
    local x, y = p.x * k, p.y * k
    local l, t = f:GetLeft(), f:GetTop()
    if l and t and math.abs(l - x) < 1 and math.abs(t - y) < 1 then return end
    -- fenetre tenue par le mode Edition : ses methodes d origine
    local clear = f.ClearAllPointsBase or f.ClearAllPoints
    local setPoint = f.SetPointBase or f.SetPoint
    pcall(clear, f)
    pcall(setPoint, f, "TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function attach(f, name)
    if handles[f] or type(f) ~= "table" or not f.CreateTexture then return end
    local h = CreateFrame("Frame", nil, f)
    h:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    h:SetPoint("TOPRIGHT", f, "TOPRIGHT", -RIGHT_FREE, 0)
    h:SetHeight(TITLE_H)
    h:SetFrameLevel(f:GetFrameLevel() + 1)
    h:EnableMouse(db.move)
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function(self)
        if not db.move or blocked(f) then return end
        pcall(f.SetMovable, f, true)
        pcall(f.SetClampedToScreen, f, true)
        self.moving = pcall(f.StartMoving, f)
    end)
    h:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self.moving = false
        pcall(f.StopMovingOrSizing, f)
        -- c est nous qui gardons la place, pas le cache de disposition du jeu
        if f.SetUserPlaced then pcall(f.SetUserPlaced, f, false) end
        save(f, name)
    end)
    h:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and db.winPos[name] then
            db.winPos[name] = nil
            ns.Say(L.SKINS_MOVE_RESET)
        end
    end)
    -- a l ouverture, puis tant qu elle est affichee (le jeu la replace)
    h:SetScript("OnShow", function()
        C_Timer.After(0, function() if f:IsShown() then place(f, name) end end)
    end)
    local acc = 0
    h:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc < 0.3 then return end
        acc = 0
        if not self.moving then place(f, name) end
    end)
    handles[f] = h
    if f:IsShown() then place(f, name) end
end

-- fenetres de la liste (celles chargees a la demande arrivent plus tard)
local function scan()
    for _, g in ipairs(ns.SKIN_GROUPS or {}) do
        for _, spec in ipairs(g.windows or {}) do
            if not spec.noHead then
                local f = _G[spec[1]]
                if f and not handles[f] then pcall(attach, f, spec[1]) end
            end
        end
    end
end

local function applyMove()
    for _, h in pairs(handles) do h:EnableMouse(db.move and true or false) end
end

-- case du panneau Habillage (Skins.lua)
function ns.MoveOptions(form)
    form:Check(L.SKINS_OPT_MOVE, function() return db and db.move end, function(v)
        if not db then return end
        db.move = v and true or false
        applyMove()
    end)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("habillage", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.skins = root.skins or {}
        db = root.skins
        if db.move == nil then db.move = true end
        if type(db.winPos) ~= "table" then db.winPos = {} end
    end
    if db then scan() end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "ADDON_LOADED")
local since = 0
ns.Every(1, function()
    if not db then return end
    scan()
end, "Habillage : Deplacer", "habillage")
