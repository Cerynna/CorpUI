--[[--------------------------------------------------------------------------
    CorpUI - module Barres (barres d action)
    Neuf barres de 12 boutons securises (type "action"), nommees d apres
    leur place par defaut (les cles enregistrees sont plus anciennes) :
      principale (main)  : emplacements 1-12, change de page avec les
                           formes, postures et camouflage (pilote d etat
                           securise, marche en combat) et les pages 1-6
      du bas 2 (bl)      : emplacements 61-72 (barre 2 du jeu), au-dessus
                           de la principale
      du bas 3 (br)      : emplacements 49-60 (barre 3 du jeu), au-dessus
      de droite (right)  : emplacements 25-36 (barre 4 du jeu), verticale,
                           au bord droit
      de droite 2        : emplacements 37-48 (barre 5 du jeu), verticale,
                           a gauche de la precedente
      supplementaires 1-3 (bar6-8) : emplacements 145-180 (barres 6 a 8 du
                           jeu), cachees au depart
      principale page 2 (bar9) : emplacements 13-24, cachee au depart
    Le panneau d options contient aussi la section du module Menus
    (ns.MenusOptions) ; /corp menus l ouvre (ns.OpenBars).
    Les sorts se glissent-deposent sur les boutons (hors combat) ; Maj +
    glisser pour retirer. Les raccourcis des barres de Blizzard sont
    rediriges vers les notres (SetOverrideBindingClick, hors combat).

    Reglages par barre : nombre de boutons, boutons par ligne, taille,
    espacement, fond (et sa marge), opacite, visible au survol seulement,
    raccourcis / noms de macro / charges affiches ou non.

    Desactive par defaut : l activer change les raccourcis clavier.
    Temps de recharge : objet de duree du client si disponible (compatible
    avec les valeurs secretes), sinon GetActionCooldown. Chiffres : decompte
    natif du cadre Cooldown (aucune duree calculee ici).

    Barre du familier : 10 boutons securises (type "pet"), visible seulement
    avec un familier (pilote d etat). Clic droit : auto-incantation, en
    cliquant le bouton du familier de Blizzard (type2 = "click" sur
    PetActionButtonN) : son propre code appelle TogglePetAutocast, que ce
    client refuse au code d un addon (10/10 : fenetre "desactiver l addon").

    Barres ajoutees par d autres fichiers (ns.AddButtonBarPlugin) : la
    barre des totems du chaman (AppelTotems.lua), avec les memes reglages.

    Visibilite par barre (toujours, combat, cible, groupe, condition de
    macro) : pilote d etat "visibility", distinct du pilote "page" de la
    barre 1. Les poignees de deplacement affichees l ignorent. La barre de
    formes (module Menus) reprend la meme condition (ns.BarVisibility).

    Bouton "Quitter le vehicule / Atterrir" : le notre, celui de Blizzard
    etant range avec MainActionBar (module Menus). Ici et pas dans Menus :
    c est un bouton d action, regle dans ce panneau et suit l activation
    des barres (c est elle qui fait cacher MainActionBar).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end

-- num : numero de la barre dans le jeu (1 a 8), plus la page 2 de la barre
-- principale (9). Les cles restent celles des premieres versions (reglages
-- deja enregistres). name : cle du nom affiche (n : le numero qu il
-- contient), d apres la place par defaut : principale en bas au centre,
-- "du bas" 2 et 3 empilees au-dessus, "de droite" au bord droit.
-- binding : commande du jeu ; sans elle (barre 9), le raccourci vise
-- directement le bouton ("CLICK nom:LeftButton").
local BARS = {
    { key = "main", num = 1, name = "BARS_MAIN",       first = 1,  binding = "ACTIONBUTTON",          paging = true, y = 150 },
    { key = "bl",   num = 2, name = "BARS_BOTTOM", n = 2, first = 61, binding = "MULTIACTIONBAR1BUTTON",              y = 194 },
    { key = "br",   num = 3, name = "BARS_BOTTOM", n = 3, first = 49, binding = "MULTIACTIONBAR2BUTTON",              y = 238 },
    -- barres de droite : verticales, collees au bord droit de l ecran
    { key = "right",  num = 4, name = "BARS_RIGHT",  first = 25, binding = "MULTIACTIONBAR3BUTTON", vertical = true, column = 0 },
    { key = "right2", num = 5, name = "BARS_RIGHT2", first = 37, binding = "MULTIACTIONBAR4BUTTON", vertical = true, column = 1 },
    -- barres 6 a 8 du jeu (emplacements 145-180) et page 2 : cachees au depart
    { key = "bar6", num = 6, name = "BARS_EXTRA", n = 1, first = 145, binding = "MULTIACTIONBAR5BUTTON", y = 300, extra = true },
    { key = "bar7", num = 7, name = "BARS_EXTRA", n = 2, first = 157, binding = "MULTIACTIONBAR6BUTTON", y = 344, extra = true },
    { key = "bar8", num = 8, name = "BARS_EXTRA", n = 3, first = 169, binding = "MULTIACTIONBAR7BUTTON", y = 388, extra = true },
    { key = "bar9", num = 9, name = "BARS_MAIN_PAGE2", first = 13, y = 432, extra = true },
}
-- ordre dans le panneau d options (toutes les cles de BARS) : la page 2
-- juste apres la principale
local PANEL_ORDER = { "main", "bar9", "bl", "br", "right", "right2", "bar6", "bar7", "bar8" }
-- barre du familier : 10 boutons, commandes BONUSACTIONBUTTON1..10
local PET_BAR = { key = "pet", pet = true, count = 10, binding = "BONUSACTIONBUTTON" }

-- Barres ajoutees par d autres fichiers du module (barre des totems :
-- AppelTotems.lua), inscrites avant PLAYER_LOGIN. Reglages, affichage,
-- deplacement, fondu et panneau d options comme les autres barres. p = {
--   key        : cle des reglages (db.bar, db.show, db.pos),
--   name()     : nom affiche,
--   pos        : position de depart, defaults : reglages de depart (une fois),
--   build(kit) : cree et renvoie le cadre (SecureHandlerStateTemplate),
--   layout(h, c, kit) : disposition (hors combat),
--   available() : faux = barre cachee (rien a y mettre),
--   count()    : nombre de boutons (impose : pas de reglage "boutons"),
--   only()     : faux = barre absente (autre classe : ni cadre ni reglages),
--   hint()     : aide ajoutee en bas du panneau,
--   blizzard   : cadres de Blizzard remplaces, caches avec l option
--                "masquer les barres de Blizzard" si la notre est affichee }
local PLUGINS = {}
function ns.AddButtonBarPlugin(p) table.insert(PLUGINS, p) end

local function barName(bar)
    if bar.plugin then return bar.plugin.name() end
    if bar.pet then return L.BARS_PET end
    local text = L[bar.name]
    if bar.n then text = string.format(text, bar.n) end
    return text
end
local PAGE_DRIVER = "[bonusbar:5] 11; [bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; "
    .. "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; 1"

-- visibilite : condition de macro par choix ("custom" : saisie libre)
local VIS_VALUES = { "always", "combat", "nocombat", "target", "group", "custom" }
local VIS_DRIVERS = {
    combat = "[combat] show; hide",
    nocombat = "[nocombat] show; hide",
    target = "[@target,exists] show; hide",
    group = "[group] show; hide",
}
-- la barre du familier se cache toujours sans familier (ou en possession :
-- la barre principale prend alors les actions)
local PET_PREFIX = "[nopet] hide; [possessbar] hide; "

-- reglages d une barre (les barres de droite : une colonne)
local BAR_DEFAULTS = {
    buttons = 12, perRow = 12, size = 36, spacing = 4,
    backdrop = false, padding = 4, bgAlpha = 75, alpha = 1, mouseover = false, oocFade = false, hideEmpty = false,
    hotkey = true, macro = false, count = true,
    cdText = true, vis = "always", visCustom = "",
}

local db
local headers = {}
local allButtons = {}
local owner = CreateFrame("Frame")
local pending = false

local function conf(key) return db.bar[key] end

-- cases vides masquees (option par barre) : elles reviennent quand on tient
-- de quoi les remplir (sort, objet, macro...), en mode raccourcis rapides et
-- avec les poignees de deplacement. Alpha seulement : permis en combat
local holding = false
local PLACEABLE = { spell = true, item = true, macro = true, petaction = true, mount = true,
                    companion = true, flyout = true, equipmentset = true, battlepet = true }
local function cursorHolds()
    local ok, kind = pcall(GetCursorInfo)
    if not ok or kind == nil or issecret(kind) then return false end
    return PLACEABLE[kind] or false
end
local function emptyAlpha(b)
    if b.hideEmpty and not holding and not ns.quickBinding and not ns.moversShown then return 0 end
    return 1
end

---------------------------------------------------------------------------
-- Rendu d un bouton
---------------------------------------------------------------------------

local function shortKey(key)  -- partage : ns.ShortKey
    if not key then return "" end
    -- modificateurs en capitales ("S1", "C2", "A3")
    key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A")
    key = key:gsub("MOUSEWHEELUP", "MwH"):gsub("MOUSEWHEELDOWN", "MwB"):gsub("BUTTON", "M")
    key = key:gsub("NUMPAD", "N"):gsub("SPACE", "Esp")
    return key
end

ns.ShortKey = shortKey

local function setCooldown(b, action)
    if C_ActionBar and C_ActionBar.GetActionCooldownDuration and b.cd.SetCooldownFromDurationObject then
        local ok, d = pcall(C_ActionBar.GetActionCooldownDuration, action)
        if ok and d and pcall(b.cd.SetCooldownFromDurationObject, b.cd, d) then return end
    end
    local ok, start, duration = pcall(GetActionCooldown, action)
    if ok and start and duration then
        if not pcall(b.cd.SetCooldown, b.cd, start, duration) then b.cd:Clear() end
    end
end

local setRangeColor   -- plus bas : couleur du raccourci selon la portee

-- Bouton du familier : icone, etat actif, auto-incantation, recharge
local function updatePet(b)
    local i = b.petIndex
    local ok, _, texture, isToken, isActive, autoAllowed, autoEnabled = pcall(GetPetActionInfo, i)
    if not ok then return end
    -- jetons (attaque, suivre...) : nom d une globale de texture
    local has = true
    if not issecret(texture) then
        has = texture ~= nil
        if has and not issecret(isToken) and isToken then texture = _G[texture] or texture end
    end
    pcall(b.icon.SetTexture, b.icon, texture)
    b.icon:SetShown(has)
    if not has then
        b.cd:Clear()
        b.active:Hide()
        b.autoMark:Hide()
        b.autoOn:Hide()
        return
    end
    b.active:SetShown((not issecret(isActive)) and isActive and true or false)
    local allowed = (not issecret(autoAllowed)) and autoAllowed and true or false
    local enabled = allowed and (not issecret(autoEnabled)) and autoEnabled and true or false
    b.autoMark:SetShown(allowed)
    if enabled then
        b.autoMark:SetColorTexture(1, 0.82, 0.1, 1)
    else
        b.autoMark:SetColorTexture(0.5, 0.45, 0.35, 0.9)
    end
    b.autoOn:SetShown(enabled)
    local okC, start, duration = pcall(GetPetActionCooldown, i)
    if okC and (issecret(start) or start) and (issecret(duration) or duration) then
        if not pcall(b.cd.SetCooldown, b.cd, start, duration) then b.cd:Clear() end
    end
    local okU, usable = pcall(GetPetActionSlotUsable, i)
    if okU and not issecret(usable) then
        if usable then b.icon:SetVertexColor(1, 1, 1) else b.icon:SetVertexColor(0.4, 0.4, 0.4) end
    end
end

local function updatePetRange(b)
    local ok, _, texture, _, _, _, _, _, checksRange, inRange = pcall(GetPetActionInfo, b.petIndex)
    setRangeColor(b, (ok and not issecret(texture) and texture and not issecret(checksRange) and not issecret(inRange)
        and checksRange and inRange == false) and true or false)
end

-- utilisable : couleur de l icone (manque de mana en bleu)
local function updateUsable(b, action)
    local okU, usable, noMana = pcall(IsUsableAction, action)
    if okU and not issecret(usable) and not issecret(noMana) then
        if usable then b.icon:SetVertexColor(1, 1, 1)
        elseif noMana then b.icon:SetVertexColor(0.4, 0.4, 1)
        else b.icon:SetVertexColor(0.4, 0.4, 0.4) end
    end
end

-- etat : action en cours ou tir automatique
local function updateState(b, action)
    local okA, active = pcall(IsCurrentAction, action)
    local okR, auto = pcall(IsAutoRepeatAction, action)
    b.active:SetShown((okA and not issecret(active) and active) or (okR and not issecret(auto) and auto) or false)
end

local function update(b)
    b.stale = nil
    if b.isPet then return updatePet(b) end
    -- boutons de sort des barres ajoutees (appel des totems...)
    if b.customUpdate then return b.customUpdate(b) end
    local action = b:GetAttribute("action")
    if not action then return end
    local tex = GetActionTexture(action)
    b.icon:SetTexture(tex)
    b.icon:SetShown(tex ~= nil)
    b.hasTex = tex ~= nil
    if not tex then
        b.count:SetText("")
        b.cd:Clear()
        b.active:Hide()
        b:SetAlpha(emptyAlpha(b))
        return
    end
    b:SetAlpha(1)
    local okC, consumable = pcall(IsConsumableAction, action)
    local okS, stackable = pcall(IsStackableAction, action)
    if (okC and consumable and not issecret(consumable)) or (okS and stackable and not issecret(stackable)) then
        local okN, n = pcall(GetActionCount, action)
        if okN and not pcall(b.count.SetFormattedText, b.count, "%d", n) then b.count:SetText("") end
    else
        b.count:SetText("")
    end
    setCooldown(b, action)
    updateUsable(b, action)
    -- nom de macro (si la barre l affiche)
    if b.macro:IsShown() then
        local okT, text = pcall(GetActionText, action)
        if not okT or not pcall(b.macro.SetText, b.macro, text or "") then b.macro:SetText("") end
    end
    updateState(b, action)
end

-- mise a jour partielle (recharge, utilisable, etat) ; familier et boutons
-- de sort des barres ajoutees : en entier (peu nombreux)
local function updatePart(b, cd, use, st)
    if b.isPet or b.customUpdate then return update(b) end
    if not b.hasTex then return end
    local action = b:GetAttribute("action")
    if not action then return end
    if cd then setCooldown(b, action) end
    if use then updateUsable(b, action) end
    if st then updateState(b, action) end
end

-- couleur du raccourci selon la portee : posee seulement si elle change
function setRangeColor(b, out)
    if b.outOfRange == out then return end
    b.outOfRange = out
    if out then b.hotkey:SetTextColor(1, 0.2, 0.2) else b.hotkey:SetTextColor(0.9, 0.9, 0.9) end
end

local function updateRange(b)
    if b.isPet then return updatePetRange(b) end
    local action = b:GetAttribute("action")
    if not action or not HasAction(action) then return end
    local ok, inRange = pcall(IsActionInRange, action)
    setRangeColor(b, (ok and not issecret(inRange) and inRange == false) and true or false)
end

local function updateHotkeys()
    for _, b in ipairs(allButtons) do
        b.hotkey:SetText(shortKey(GetBindingKey(b.bindCommand)))
    end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local makeVisuals    -- plus bas : apparence commune des boutons

local function makeButton(header, bar, j)
    local name = "CorpUIBar" .. bar.key .. "Button" .. j
    local b = CreateFrame("Button", name, header, "SecureActionButtonTemplate")
    -- taille et position : layout()
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:RegisterForDrag("LeftButton")
    b:SetAttribute("type", "action")
    b:SetAttribute("index", j)
    b:SetAttribute("action", bar.first + j - 1)
    if bar.paging then
        b:SetAttribute("_childupdate-actionpage", [[
            self:SetAttribute("action", (message - 1) * 12 + self:GetAttribute("index"))
        ]])
    end
    b.bindingName = bar.binding and (bar.binding .. j) or nil
    -- commande visee par un raccourci (mode raccourcis rapides, affichage)
    b.bindCommand = b.bindingName or ("CLICK " .. name .. ":LeftButton")
    b.header = header
    b.bindLabel = barName(bar) .. " - " .. j
    if ns.RegisterBindable then ns.RegisterBindable(b, b.bindCommand) end
    makeVisuals(b)

    -- la page change dans le code securise : on suit l attribut
    b:HookScript("OnAttributeChanged", function(self, attr)
        if attr == "action" then update(self) end
    end)
    b:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        if db.lockButtons and not IsShiftKeyDown() then return end
        PickupAction(self:GetAttribute("action"))
        update(self)
    end)
    b:SetScript("OnReceiveDrag", function(self)
        if InCombatLockdown() then return end
        PlaceAction(self:GetAttribute("action"))
        update(self)
    end)
    b:SetScript("OnEnter", function(self)
        if ns.QuickBindHover and ns.QuickBindHover(self) then return end
        local t = ns.Tooltip(self, "ANCHOR_TOPRIGHT")
        if not pcall(t.SetAction, t, self:GetAttribute("action")) then t:Hide() return end
        t:Show()
    end)
    b:SetScript("OnLeave", ns.HideTooltip)
    table.insert(allButtons, b)
    return b
end

-- Bouton du familier : clic gauche securise (CastPetAction) ; clic droit :
-- le bouton du familier de Blizzard (PetActionButtonN, meme numero) est
-- clique par l action securisee "click" ; son code (PetActionBar.lua,
-- branche forever) appelle TogglePetAutocast, protegee sur ce client
local function makePetButton(header, bar, j)
    local name = "CorpUIBarpetButton" .. j
    local b = CreateFrame("Button", name, header, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:RegisterForDrag("LeftButton")
    b:SetAttribute("type", "pet")
    b:SetAttribute("index", j)
    b:SetAttribute("action", j)
    local blizz = _G["PetActionButton" .. j]
    if type(blizz) == "table" and blizz.Click then
        b:SetAttribute("type2", "click")
        b:SetAttribute("clickbutton2", blizz)
    end
    b.isPet, b.petIndex = true, j
    b.bindingName = bar.binding .. j
    b.bindCommand = b.bindingName
    b.header = header
    b.bindLabel = barName(bar) .. " - " .. j
    if ns.RegisterBindable then ns.RegisterBindable(b, b.bindCommand) end
    makeVisuals(b)
    -- auto-incantation : coin dore (possible : terne ; activee : vif + liseré),
    -- dans un cadre au-dessus de la recharge
    local layer = CreateFrame("Frame", nil, b)
    layer:SetAllPoints()
    layer:SetFrameLevel(b.cd:GetFrameLevel() + 1)
    b.autoMark = layer:CreateTexture(nil, "OVERLAY")
    b.autoMark:SetSize(7, 7)
    b.autoMark:SetPoint("TOPLEFT", 2, -2)
    b.autoMark:Hide()
    b.autoOn = CreateFrame("Frame", nil, layer)
    b.autoOn:SetAllPoints()
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                            { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = b.autoOn:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 0.82, 0.1, 0.9)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if side[3] then t:SetHeight(2) else t:SetWidth(2) end
    end
    b.autoOn:Hide()

    b:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        if db.lockButtons and not IsShiftKeyDown() then return end
        pcall(PickupPetAction, self.petIndex)
        update(self)
    end)
    b:SetScript("OnReceiveDrag", function(self)
        if InCombatLockdown() then return end
        local ok, kind = pcall(GetCursorInfo)
        if ok and kind == "petaction" then pcall(PickupPetAction, self.petIndex) end
        update(self)
    end)
    b:SetScript("OnEnter", function(self)
        if ns.QuickBindHover and ns.QuickBindHover(self) then return end
        local t = ns.Tooltip(self, "ANCHOR_TOPRIGHT")
        if not pcall(t.SetPetAction, t, self.petIndex) then t:Hide() return end
        t:Show()
    end)
    b:SetScript("OnLeave", ns.HideTooltip)
    table.insert(allButtons, b)
    return b
end

-- Apparence commune : icone, recharge, textes
makeVisuals = function(b)
    ns.UI.Skin(b, 0.6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.active = b:CreateTexture(nil, "OVERLAY")
    b.active:SetAllPoints()
    b.active:SetColorTexture(1, 0.85, 0.2, 0.25)
    b.active:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)
    b.hotkey = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    b.hotkey:SetPoint("TOPRIGHT", -2, -2)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.macro = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    b.macro:SetPoint("BOTTOMLEFT", 2, 2)
    b.macro:SetPoint("BOTTOMRIGHT", -2, 2)
    b.macro:SetWordWrap(false)
    b.macro:Hide()
end

-- Textes d un bouton affiche selon les reglages de sa barre
local function styleButton(b, c)
    local font = math.max(8, math.floor(c.size * 0.3 + 0.5))
    b.hideEmpty = c.hideEmpty
    b.hotkey:SetShown(c.hotkey)
    b.count:SetShown(c.count)
    b.macro:SetShown(c.macro)
    -- textes a l echelle du bouton
    local f, _, flags = b.hotkey:GetFont()
    if f then b.hotkey:SetFont(f, font, flags) end
    f, _, flags = b.macro:GetFont()
    if f then b.macro:SetFont(f, math.max(7, font - 1), flags) end
    -- chiffres de recharge : decompte natif du cadre Cooldown
    pcall(b.cd.SetHideCountdownNumbers, b.cd, not c.cdText)
    if c.cdText and b.cd.GetCountdownFontString then
        local okF, fs = pcall(b.cd.GetCountdownFontString, b.cd)
        if okF and fs and fs.SetFont then
            local cf, _, cflags = fs:GetFont()
            pcall(fs.SetFont, fs, cf or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
                math.max(9, math.floor(c.size * 0.42 + 0.5)), cflags or "OUTLINE")
        end
    end
end

-- outils prets pour les barres ajoutees (ns.AddButtonBarPlugin)
local kit

-- Disposition d une barre selon ses reglages (hors combat : boutons securises)
-- (barres ajoutees comprises : tous les boutons, seuls les sautes visibles)
local function catchUp()
    for _, b in ipairs(allButtons) do
        if b.stale and b:IsVisible() then update(b) end
    end
end

local function layout(h)
    if not h.catchUpHooked then
        h.catchUpHooked = true
        h:HookScript("OnShow", catchUp)
    end
    local c = conf(h.bar.key)
    if h.bar.plugin then return h.bar.plugin.layout(h, c, kit) end
    ns.LayoutButtonBar(h, h.buttons, c.buttons, c, db.pos[h.bar.key])
    for j, b in ipairs(h.buttons) do
        if j <= c.buttons then
            b:Show()
            styleButton(b, c)
            update(b)
        else
            b:Hide()
        end
    end
end

local function buildPlugin(p)
    db.pos[p.key] = db.pos[p.key] or { point = p.pos.point, x = p.pos.x, y = p.pos.y }
    local ok, h = pcall(p.build, kit)
    if not ok then geterrorhandler()(h) return end
    if not h then return end
    h.bar = { key = p.key, plugin = p }
    ns.ApplyPos(h, db.pos[p.key])
    layout(h)
    ns.UI.Mover(h, db.pos[p.key], p.name())
    table.insert(ns.ButtonBars, { frame = h, conf = function() return conf(p.key) end })
    table.insert(headers, h)
end

local function build()
    for i, bar in ipairs(BARS) do
        local c = conf(bar.key)
        if bar.vertical then
            db.pos[bar.key] = db.pos[bar.key] or { point = "RIGHT", x = -6 - bar.column * (c.size + c.spacing), y = 0 }
        else
            db.pos[bar.key] = db.pos[bar.key] or { point = "BOTTOM", x = 0, y = bar.y }
        end
        local h = CreateFrame("Frame", "CorpUIBar" .. bar.key, UIParent, "SecureHandlerStateTemplate")
        h:SetSize(1, 1)
        ns.ApplyPos(h, db.pos[bar.key])
        -- fond facultatif : obsidienne et liseré du theme
        h.backBorder, h.back = ns.UI.Skin(h, 0.75, false)
        h.bar = bar
        h.buttons = {}
        for j = 1, 12 do h.buttons[j] = makeButton(h, bar, j) end
        layout(h)
        if bar.paging then
            h:SetAttribute("_onstate-page", [[
                self:SetAttribute("actionpage", newstate)
                control:ChildUpdate("actionpage", newstate)
            ]])
        end
        ns.UI.Mover(h, db.pos[bar.key], barName(bar))
        table.insert(ns.ButtonBars, { frame = h, conf = function() return conf(bar.key) end })
        headers[i] = h
    end
    -- barre du familier : a droite de la barre des formes
    local bar = PET_BAR
    db.pos.pet = db.pos.pet or { point = "BOTTOM", x = 170, y = 284 }
    local h = CreateFrame("Frame", "CorpUIBarpet", UIParent, "SecureHandlerStateTemplate")
    h:SetSize(1, 1)
    ns.ApplyPos(h, db.pos.pet)
    h.backBorder, h.back = ns.UI.Skin(h, 0.75, false)
    h.bar = bar
    h.buttons = {}
    for j = 1, bar.count do h.buttons[j] = makePetButton(h, bar, j) end
    layout(h)
    ns.UI.Mover(h, db.pos.pet, barName(bar))
    table.insert(ns.ButtonBars, { frame = h, conf = function() return conf(bar.key) end })
    table.insert(headers, h)
    -- barres ajoutees (barre des totems...) ; celles d une autre classe : rien
    for _, p in ipairs(PLUGINS) do
        if not p.only or p.only() then buildPlugin(p) end
    end
end

-- Condition choisie dans les reglages d une barre (nil : toujours visible)
local function userCondition(c)
    if not c then return nil end
    local cond
    if c.vis == "custom" then
        cond = strtrim(c.visCustom or "")
        if cond == "" then cond = nil end
    else
        cond = VIS_DRIVERS[c.vis]
    end
    -- condition saisie illisible par le jeu : ignoree
    if cond and SecureCmdOptionParse and not pcall(SecureCmdOptionParse, cond) then cond = nil end
    return cond
end

-- partage : la barre de formes (module Menus) s en sert pour son pilote
ns.BarVisibility = userCondition

-- Condition de visibilite d une barre (nil : toujours visible)
local function visCondition(bar, c)
    local cond = userCondition(c)
    if bar.pet then return PET_PREFIX .. (cond or "show") end
    return cond
end

---------------------------------------------------------------------------
-- Bouton "Quitter le vehicule / Atterrir"
-- Celui de Blizzard (MainMenuBarVehicleLeaveButton) est un enfant de
-- MainActionBar, que le module Menus range au parent cache : on a le notre.
-- Bouton securise type "leavevehicle" (action securisee de Blizzard, qui
-- appelle VehicleExit, comme /leavevehicle). Affiche par le pilote d etat
-- [canexitvehicle] (CanExitVehicle : ce qui montre aussi celui de Blizzard).
-- Vol de taxi : le bouton de Blizzard appelle alors TaxiRequestEarlyLanding
-- (fonction non protegee) au lieu de VehicleExit ; on fait pareil dans
-- PreClick, et hors combat l action securisee est sautee pour ce clic.
---------------------------------------------------------------------------

local VEHICLE_DRIVER = "[canexitvehicle] show; hide"
local VEHICLE_ACTION = "leavevehicle"
local vehicleButton

local function onTaxi()
    if not UnitOnTaxi then return false end
    local ok, v = pcall(UnitOnTaxi, "player")
    return ok and not issecret(v) and v and true or false
end

-- atterrissage demande : icone grisee jusqu a ce que le bouton se cache
local function setLanding(b, v)
    b.landing = v
    b.icon:SetDesaturated(v and true or false)
    b.icon:SetAlpha(v and 0.6 or 1)
end

local function buildVehicle()
    local c = db.vehicle
    db.pos.vehicle = db.pos.vehicle or { point = "BOTTOM", x = -270, y = 150 }
    local b = CreateFrame("Button", "CorpUIVehicleLeave", UIParent, "SecureActionButtonTemplate")
    b:SetSize(c.size, c.size)
    ns.ApplyPos(b, db.pos.vehicle)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", VEHICLE_ACTION)
    ns.UI.Skin(b, 0.6)
    -- icones CorpUI : sortir du vehicule, ou atterrir (taxi)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)
    function b.SyncIcon(self)
        self.icon:SetTexture(ns.MEDIA .. (onTaxi() and "vehicle_land" or "vehicle_exit"))
    end
    b:SyncIcon()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon)
    hl:SetColorTexture(1, 1, 1, 0.2)
    b:SetScript("PreClick", function(self, _, down)
        -- un clic = appui + relachement : l action part sur l un des deux
        if (down and true or false) ~= GetCVarBool("ActionButtonUseKeyDown") then return end
        if not onTaxi() then return end
        if self.landing then return end
        if TaxiRequestEarlyLanding then pcall(TaxiRequestEarlyLanding) end
        setLanding(self, true)
        -- pas de VehicleExit en plus pour ce clic (attribut : hors combat)
        if not InCombatLockdown() then
            self:SetAttribute("type", nil)
            self.skipped = true
        end
    end)
    b:SetScript("PostClick", function(self)
        if self.skipped and not InCombatLockdown() then
            self:SetAttribute("type", VEHICLE_ACTION)
            self.skipped = nil
        end
    end)
    b:SetScript("OnHide", function(self) setLanding(self, false) end)
    b:SetScript("OnShow", function(self) self:SyncIcon() end)
    b:SetScript("OnEnter", function(self)
        local C = ns.COLORS
        if self.cuiBorder then self.cuiBorder:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1) end
        local t = ns.Tooltip(self, "ANCHOR_TOPRIGHT")
        if onTaxi() then
            t:AddLine(TAXI_CANCEL or L.BARS_VEHICLE_LAND)
            if TAXI_CANCEL_DESCRIPTION then t:AddLine(TAXI_CANCEL_DESCRIPTION, 1, 0.82, 0, true) end
        else
            t:AddLine(LEAVE_VEHICLE or L.BARS_VEHICLE)
        end
        t:Show()
    end)
    b:SetScript("OnLeave", function(self)
        ns.UI.ResetBorder(self)
        ns.HideTooltip()
    end)
    ns.UI.Mover(b, db.pos.vehicle, L.BARS_VEHICLE)
    vehicleButton = b
end

-- Hors combat : taille, echelle, affichage (case, puis pilote d etat ;
-- poignees de deplacement affichees : bouton visible pour le placer)
local function applyVehicle()
    local b = vehicleButton
    if not b then return end
    local c = db.vehicle
    b:SetScale(db.scale)
    b:SetSize(c.size, c.size)
    b:SetAttribute("type", VEHICLE_ACTION)
    b.skipped = nil
    local on = db.enabled and c.show
    if on and not ns.moversShown then
        RegisterStateDriver(b, "visibility", VEHICLE_DRIVER)
    else
        UnregisterStateDriver(b, "visibility")
        b:SetShown(on and true or false)
    end
end

-- Affichage d une barre : case "afficher" d abord, puis la condition
-- (poignees de deplacement affichees : barre visible pour la placer)
local function applyVisibility(h)
    local on = db.enabled and db.show[h.bar.key]
    -- barre ajoutee sans rien a montrer (pas chaman...) : cachee, meme
    -- avec les poignees de deplacement
    if on and h.bar.plugin and h.bar.plugin.available and not h.bar.plugin.available() then on = false end
    local cond = on and not ns.moversShown and visCondition(h.bar, conf(h.bar.key))
    if cond then
        RegisterStateDriver(h, "visibility", cond)
    else
        UnregisterStateDriver(h, "visibility")
        h:SetShown(on and true or false)
    end
end

---------------------------------------------------------------------------
-- Activation, raccourcis, barres de Blizzard (hors combat)
---------------------------------------------------------------------------

local function applyBindings()
    ClearOverrideBindings(owner)
    if not db.enabled or not db.bindings then return end
    for _, b in ipairs(allButtons) do
        -- boutons retires de la barre (reglage "boutons") : raccourci laisse au jeu
        local h = b.header
        if b.bindingName and b:GetAttribute("index") <= conf(h.bar.key).buttons and db.show[h.bar.key] then
            for _, key in ipairs({ GetBindingKey(b.bindingName) }) do
                SetOverrideBindingClick(owner, false, key, b:GetName(), "LeftButton")
            end
        end
    end
end

local BLIZZ = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }
for i = 1, 12 do table.insert(BLIZZ, "ActionButton" .. i) end

local function apply()
    if InCombatLockdown() then pending = true return end
    pending = false
    for _, h in ipairs(headers) do
        local on = db.enabled and db.show[h.bar.key]
        if h.bar.paging then
            if on then RegisterStateDriver(h, "page", PAGE_DRIVER) else UnregisterStateDriver(h, "page") end
        end
        applyVisibility(h)
        h:SetScale(db.scale)
        layout(h)
    end
    applyVehicle()
    applyBindings()
    updateHotkeys()
    for _, b in ipairs(allButtons) do update(b) end
    if db.hideBlizzard or db.blizzardHidden then
        ns.HideBlizzard(BLIZZ, db.enabled and db.hideBlizzard)
        db.blizzardHidden = db.enabled and db.hideBlizzard
    end
    -- barre du familier de Blizzard : masquee seulement si la notre est affichee
    local hidePet = db.enabled and db.hideBlizzard and db.show.pet and true or false
    if hidePet or db.petBlizzHidden then
        ns.HideBlizzard({ "PetActionBar" }, hidePet)
        db.petBlizzHidden = hidePet
    end
    -- barres ajoutees : leur equivalent de Blizzard, de meme
    for _, p in ipairs(PLUGINS) do
        if p.blizzard then
            local hideP = db.enabled and db.hideBlizzard and db.show[p.key] and true or false
            db.pluginBlizzHidden = db.pluginBlizzHidden or {}
            if hideP or db.pluginBlizzHidden[p.key] then
                ns.HideBlizzard(p.blizzard, hideP)
                db.pluginBlizzHidden[p.key] = hideP or nil
            end
        end
    end
end

kit = {
    conf = conf,
    makeVisuals = function(b) makeVisuals(b) end,
    style = styleButton,
    update = update,
    -- bouton de barre : evenements des barres, raccourcis affiches, portee
    addButton = function(b) table.insert(allButtons, b) end,
    apply = function() apply() end,
    -- une seule barre a revoir (ses boutons ont change) : hors combat
    refresh = function(h)
        if InCombatLockdown() then pending = true return end
        applyVisibility(h)
        layout(h)
    end,
    pos = function(key) return db.pos[key] end,
    db = function() return db end,
}

-- poignees de deplacement affichees / masquees : visibilite a revoir
local lastMovers = false
ns.Listen(function()
    if not db or (ns.moversShown and true or false) == lastMovers then return end
    lastMovers = ns.moversShown and true or false
    if InCombatLockdown() then pending = true return end
    for _, h in ipairs(headers) do
        applyVisibility(h)
        -- barres ajoutees : apercu complet pendant le deverrouillage
        if h.bar.plugin then layout(h) end
    end
    applyVehicle()
end)

-- cases vides : revoir leur alpha quand le mode raccourcis ou les poignees
-- changent (pas de combat a attendre : alpha seulement)
local lastShowAll = false
ns.Listen(function()
    local all = (ns.quickBinding or ns.moversShown) and true or false
    if not db or all == lastShowAll then return end
    lastShowAll = all
    for _, b in ipairs(allButtons) do
        if not b.isPet then update(b) end
    end
end)

---------------------------------------------------------------------------
-- Fenetre d options
---------------------------------------------------------------------------

local win

local function buildWindow()
    win = ns.UI.Window("CorpUIBarsOptions", ns.TITLE .. " - " .. L.MOD_BARS, nil, 440, 700)
    -- barres reglables : les 9 barres d action (ordre du panneau), celle du
    -- familier, puis celles du module Menus
    local byKey = {}
    for _, bar in ipairs(BARS) do byKey[bar.key] = bar end
    local targets = {}
    for _, key in ipairs(PANEL_ORDER) do
        local bar = byKey[key]
        table.insert(targets, {
            label = barName(bar),
            conf = function() return conf(bar.key) end,
            shown = function() return db.show[bar.key] end,
            setShown = function(v) db.show[bar.key] = v end,
        })
    end
    table.insert(targets, {
        label = barName(PET_BAR), pet = true,
        conf = function() return conf("pet") end,
        shown = function() return db.show.pet end,
        setShown = function(v) db.show.pet = v end,
    })
    for _, p in ipairs(PLUGINS) do
        if not p.only or p.only() then table.insert(targets, {
            label = p.name(), plugin = p,
            conf = function() return conf(p.key) end,
            shown = function() return db.show[p.key] end,
            setShown = function(v) db.show[p.key] = v end,
        }) end
    end
    -- barres du module Menus (formes, micro-menu, sacs) : pas de chiffres de recharge
    for _, x in ipairs(ns.ExtraButtonBars or {}) do
        table.insert(targets, {
            label = x.label(), stance = true,
            conf = x.conf, shown = x.shown, setShown = x.setShown,
        })
    end
    local form = ns.UI.Form(win, -34, function()
        if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
        apply()
        if ns.MenusApply then ns.MenusApply() end
    end)

    -- general
    form:Header(L.BARS_GENERAL)
    form:Check(L.BARS_OPT_ENABLE, function() return db.enabled end, function(v) db.enabled = v end)
    form:Check(L.BARS_OPT_BINDINGS, function() return db.bindings end, function(v) db.bindings = v end)
    form:Check(L.BARS_OPT_LOCK, function() return db.lockButtons end, function(v) db.lockButtons = v end)
    form:Check(L.BARS_OPT_BLIZZ, function() return db.hideBlizzard end, function(v) db.hideBlizzard = v end)
    form:Columns(2)
    form:Number(L.FRAMES_SCALE, function() return db.scale end, function(v) db.scale = v end, 0.6, 1.6, 0.1)
    form:EndColumns()

    -- raccourcis rapides
    local kb = ns.UI.Button(win, L.KB_BUTTON, 160, function() ns.QuickBind(true) end)
    kb:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 2)
    local kbHint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    kbHint:SetPoint("LEFT", kb, "RIGHT", 8, 0)
    kbHint:SetPoint("RIGHT", win, "RIGHT", -8, 0)
    kbHint:SetJustifyH("LEFT")
    kbHint:SetText(L.KB_SHORT)
    form:Gap(32)

    -- barres affichees (deux colonnes : place pour les noms)
    form:Header(L.BARS_SHOWN)
    form:Columns(2)
    for _, t in ipairs(targets) do form:Check(t.label, t.shown, t.setShown) end
    form:EndColumns()

    -- micro-menu, sacs et postures (module Menus) : remplacement et
    -- interface de Blizzard ; l affichage de ces barres est dans la grille
    if ns.MenusOptions then
        form:Gap(4)
        form.y = ns.MenusOptions(win, form.y)
    end

    -- reglages de la barre choisie (liste deroulante)
    form:Gap(4)
    form:Header(L.BARS_PERBAR)
    local sel = 1
    local function cur() return targets[sel].conf() end
    local picker = form:Select(nil, function()
        local list = {}
        for i, t in ipairs(targets) do table.insert(list, { value = i, text = t.label }) end
        return list
    end, function() return sel end, function(v) sel = v end, 200)
    -- recopier l apparence de cette barre sur les autres (pas leur forme)
    local copy = ns.UI.Button(win, L.BARS_COPY, 120, function()
        if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
        local c = cur()
        for _, t in ipairs(targets) do
            local o = t.conf()
            for _, k in ipairs({ "size", "spacing", "backdrop", "padding", "bgAlpha", "alpha", "mouseover", "oocFade", "hideEmpty", "hotkey", "macro", "count", "cdText" }) do
                if c[k] ~= nil and (o[k] ~= nil or k == "oocFade") then o[k] = c[k] end
            end
        end
        form.Changed()
    end)
    copy:SetPoint("LEFT", picker, "RIGHT", 8, 0)

    local function num(fmt, key, lo, hi, step)
        form:Number(fmt, function() return cur()[key] or 0 end, function(v) cur()[key] = v end, lo, hi, step)
    end
    local function chk(text, key)
        form:Check(text, function() return cur()[key] end, function(v) cur()[key] = v end)
    end
    -- afficher ou non la barre : la grille "Barres affichees" plus haut
    form:Columns(2)
    -- barre ajoutee (totems) : ses boutons sont ceux que le jeu donne
    form:Number(L.BARS_BUTTONS, function()
        local p = targets[sel].plugin
        if p and p.count then return p.count() end
        return cur().buttons or 0
    end, function(v) if not targets[sel].plugin then cur().buttons = v end end, 1, 16)
    num(L.BARS_PERROW, "perRow", 1, 16)
    num(L.BARS_SIZE, "size", 16, 64)
    num(L.BARS_SPACING, "spacing", 0, 20)
    form:Number(L.BARS_ALPHA, function() return math.floor((cur().alpha or 1) * 100 + 0.5) end,
        function(v) cur().alpha = v / 100 end, 10, 100, 5)
    -- le fond, puis son opacite et sa marge
    chk(L.BARS_BACKDROP, "backdrop")
    num(L.BARS_BGALPHA, "bgAlpha", 0, 100, 5)
    num(L.BARS_PADDING, "padding", 0, 20)
    chk(L.BARS_MOUSEOVER, "mouseover")
    chk(L.BARS_OOC_FADE, "oocFade")
    -- cases vides : barres d action seulement (pas le familier, les formes
    -- ni les totems : une case vide s y remplit par sa fleche)
    local function slots() return not targets[sel].stance and not targets[sel].pet and not targets[sel].plugin end
    form:Check(L.BARS_HIDE_EMPTY, function() return slots() and cur().hideEmpty end,
        function(v) if slots() then cur().hideEmpty = v end end)
    chk(L.BARS_HOTKEY, "hotkey")
    chk(L.BARS_MACRO, "macro")
    chk(L.BARS_COUNT, "count")
    -- chiffres de recharge : barres d action et du familier (pas la barre de formes)
    local function own() return not targets[sel].stance end
    form:Check(L.BARS_CDTEXT, function() return own() and cur().cdText end,
        function(v) if own() then cur().cdText = v end end)
    local visNames = {
        always = L.BARS_VIS_ALWAYS, combat = L.BARS_VIS_COMBAT, nocombat = L.BARS_VIS_NOCOMBAT,
        target = L.BARS_VIS_TARGET, group = L.BARS_VIS_GROUP, custom = L.BARS_VIS_CUSTOM,
    }
    form:Cycle(L.BARS_VIS, VIS_VALUES, visNames, function() return cur().vis or "always" end,
        function(v) cur().vis = v end)
    form:EndColumns()

    -- condition personnalisee : saisie validee par Entree (ou en quittant)
    local condLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    condLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 4)
    condLabel:SetText(L.BARS_VIS_COND)
    local edit = CreateFrame("EditBox", nil, win)
    edit:SetSize(300, 20)
    edit:SetPoint("TOPLEFT", win, "TOPLEFT", 120, form.y)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetTextInsets(4, 4, 0, 0)
    edit:SetMaxLetters(255)
    ns.UI.Skin(edit, 0.8)
    local function editable() return cur().vis == "custom" end
    local function refreshEdit()
        if not edit:HasFocus() then edit:SetText(cur().visCustom or "") end
        edit:SetAlpha(editable() and 1 or 0.4)
    end
    local function commit(self)
        if not editable() then refreshEdit() return end
        local v = strtrim(self:GetText() or "")
        if v ~= (cur().visCustom or "") then
            cur().visCustom = v
            form.Changed()
        end
    end
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function(self) if not editable() then self:ClearFocus() end end)
    edit:SetScript("OnEditFocusLost", function(self) commit(self) refreshEdit() end)
    table.insert(form.refreshers, refreshEdit)
    form.y = form.y - 26
    local condHint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    condHint:SetPoint("TOPLEFT", win, "TOPLEFT", 120, form.y)
    condHint:SetText(L.BARS_VIS_EXAMPLE)
    form.y = form.y - 16

    -- bouton de sortie de vehicule / atterrissage
    form:Gap(4)
    form:Header(L.BARS_VEHICLE)
    form:Columns(2)
    form:Check(L.BARS_VEHICLE_SHOW, function() return db.vehicle.show end, function(v) db.vehicle.show = v end)
    form:Number(L.BARS_SIZE, function() return db.vehicle.size end, function(v) db.vehicle.size = v end, 16, 64)
    form:EndColumns()

    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    -- MENUS_HINT : deplacer les barres, touches des postures (module Menus)
    local extra = ""
    for _, p in ipairs(PLUGINS) do
        if p.hint then extra = extra .. " " .. p.hint() end
    end
    hint:SetText(L.BARS_HINT .. " " .. L.BARS_STEP_HINT .. " " .. L.BARS_PET_HINT .. " " .. L.BARS_VEHICLE_HINT
        .. extra .. " " .. L.MENUS_HINT)
    win:SetHeight(math.max(700, -form.y + 90))

    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

-- partage : /corp menus ouvre ce panneau (le module Menus n en a plus)
ns.OpenBars = toggle

---------------------------------------------------------------------------

-- evenements du familier (ceux qu ecoute la barre de Blizzard)
local PET_EVENTS = {
    PET_BAR_UPDATE = true, PET_BAR_UPDATE_COOLDOWN = true, PET_BAR_UPDATE_USABLE = true,
    PET_UI_UPDATE = true, UNIT_PET = true, UNIT_FLAGS = true, UNIT_AURA = true,
    PLAYER_CONTROL_LOST = true, PLAYER_CONTROL_GAINED = true, PLAYER_FARSIGHT_FOCUS_CHANGED = true,
    UPDATE_VEHICLE_ACTIONBAR = true, PLAYER_MOUNT_DISPLAY_CHANGED = true,
}

-- Rafales : recharge, utilisable et etat arrivent par paquets (sort lance :
-- SPELL_UPDATE_COOLDOWN, ACTIONBAR_UPDATE_COOLDOWN, ..._STATE, ..._USABLE
-- dans la meme image). Une seule passe a l image suivante, et seulement la
-- partie demandee ; boutons caches sautes (rattrapes a l affichage).
local PART_OF = {
    ACTIONBAR_UPDATE_COOLDOWN = "cd", SPELL_UPDATE_COOLDOWN = "cd",
    ACTIONBAR_UPDATE_USABLE = "use", SPELL_UPDATE_USABLE = "use",
    ACTIONBAR_UPDATE_STATE = "st",
}
local want = {}
local flusher = CreateFrame("Frame")
flusher:Hide()
flusher:SetScript("OnUpdate", function(self)
    self:Hide()
    local full, cd, use, st = want.full, want.cd, want.use, want.st
    want.full, want.cd, want.use, want.st = nil, nil, nil, nil
    if not db or not db.enabled then return end
    for _, b in ipairs(allButtons) do
        if not b:IsVisible() then
            b.stale = true
        elseif full or b.stale then
            update(b)
        else
            updatePart(b, cd, use, st)
        end
    end
end)
local function queue(kind)
    want[kind] = true
    flusher:Show()
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, arg)
    if ns.ModuleOff("barres", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.bars = root.bars or {}
        db = root.bars
        db.pos = db.pos or {}
        db.show = db.show or { main = true, bl = true, br = true }
        -- barres de droite ajoutees le 05/10 : affichees par defaut
        if db.show.right == nil then db.show.right = true end
        if db.show.right2 == nil then db.show.right2 = true end
        for _, bar in ipairs(BARS) do
            if bar.extra and db.show[bar.key] == nil then db.show[bar.key] = false end
        end
        if db.enabled == nil then db.enabled = false end
        if db.bindings == nil then db.bindings = true end
        if db.lockButtons == nil then db.lockButtons = true end
        -- l interface de Blizzard qu on remplace est masquee par defaut (une fois)
        if not db.blizzDefault2 then
            db.hideBlizzard = true
            db.blizzDefault2 = true
        end
        db.scale = db.scale or 1
        -- reglages par barre (l ancienne taille commune sert de depart)
        db.bar = db.bar or {}
        for _, bar in ipairs(BARS) do
            local c = db.bar[bar.key] or {}
            db.bar[bar.key] = c
            for k, v in pairs(BAR_DEFAULTS) do
                if c[k] == nil then c[k] = v end
            end
            if not c._init then
                c._init = true
                c.size = db.size or BAR_DEFAULTS.size
                if bar.vertical then c.perRow = 1 end
            end
        end
        -- barre du familier (ajoutee le 05/10) : affichee, 10 boutons plus petits
        if db.show.pet == nil then db.show.pet = true end
        local pc = db.bar.pet or {}
        db.bar.pet = pc
        if not pc._init then
            pc._init = true
            pc.buttons, pc.perRow, pc.size = 10, 10, 30
        end
        for k, v in pairs(BAR_DEFAULTS) do
            if pc[k] == nil then pc[k] = v end
        end
        -- barres ajoutees (barre des totems, 09/10) : affichees, leurs
        -- reglages de depart une fois
        for _, p in ipairs(PLUGINS) do
            if db.show[p.key] == nil then db.show[p.key] = true end
            local c = db.bar[p.key] or {}
            db.bar[p.key] = c
            if not c._init then
                c._init = true
                for k, v in pairs(p.defaults or {}) do c[k] = v end
            end
            for k, v in pairs(BAR_DEFAULTS) do
                if c[k] == nil then c[k] = v end
            end
        end
        -- bouton de sortie de vehicule (ajoute le 05/10) : affiche, 36 px
        db.vehicle = db.vehicle or {}
        if db.vehicle.show == nil then db.vehicle.show = true end
        db.vehicle.size = db.vehicle.size or 36
        build()
        buildVehicle()
        apply()
    elseif not db then
        return
    elseif not db.enabled and event ~= "PLAYER_REGEN_ENABLED" and event ~= "UPDATE_BINDINGS" then
        -- barres CorpUI coupees : leurs boutons ne sont pas affiches
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then apply() end
    elseif event == "UPDATE_BINDINGS" then
        if InCombatLockdown() then pending = true else applyBindings() updateHotkeys() end
    elseif event == "ACTIONBAR_SHOWGRID" or event == "ACTIONBAR_HIDEGRID" or event == "CURSOR_CHANGED" then
        local was = holding
        if event == "ACTIONBAR_SHOWGRID" then holding = true
        elseif event == "ACTIONBAR_HIDEGRID" then holding = false
        else holding = cursorHolds() end
        if holding ~= was then
            for _, b in ipairs(allButtons) do
                if not b.isPet then
                    if b:IsVisible() then update(b) else b.stale = true end
                end
            end
        end
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        for _, b in ipairs(allButtons) do
            if not b.isPet and b:GetAttribute("action") == arg then update(b) end
        end
    elseif PET_EVENTS[event] then
        if event == "UNIT_PET" and arg ~= "player" then return end
        for _, b in ipairs(allButtons) do
            if b.isPet then
                if b:IsVisible() then update(b) else b.stale = true end
            end
        end
    else
        queue(PART_OF[event] or "full")
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED",
                     "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_COOLDOWN",
                     "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "UPDATE_SHAPESHIFT_FORM",
                     "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_TARGET_CHANGED",
                     "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID", "CURSOR_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
for e in pairs(PET_EVENTS) do
    if e == "UNIT_FLAGS" or e == "UNIT_AURA" then
        pcall(ev.RegisterUnitEvent, ev, e, "pet")
    else
        pcall(ev.RegisterEvent, ev, e)
    end
end

-- portee : cinq fois par seconde
ns.Every(0.2, function()
    if not db or not db.enabled then return end
    for _, b in ipairs(allButtons) do
        if b:IsVisible() then updateRange(b) end
    end
end, "Barres : portee")

ns.RegisterModule({
    command = "barres",
    panelName = "CorpUIBarsOptions",
    icon = "Interface\\Icons\\INV_Misc_Book_11",
    title = function() return L.MOD_BARS end,
    desc = function() return L.BARS_DESC end,
    Slash = function(input)
        local cmd = strlower(strtrim(input or ""))
        if cmd == "kb" or cmd == "raccourcis" then ns.QuickBind(true) else toggle() end
    end,
    Open = toggle,
})
