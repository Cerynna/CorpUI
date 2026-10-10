--[[--------------------------------------------------------------------------
    CorpUI - raccourcis rapides (facon ElvUI /kb)
    Mode active depuis les options des barres ou /corp kb :
      - survoler un bouton (barres d action, barre de formes) l entoure d or
        et affiche ses raccourcis ;
      - appuyer sur une touche (avec Maj / Ctrl / Alt), la molette ou un
        bouton de souris (milieu, 4, 5) lui donne ce raccourci ;
      - Echap retire tous les raccourcis du bouton ;
      - "Enregistrer" garde les changements, "Annuler" revient aux
        raccourcis d avant.
    Les raccourcis sont ceux du jeu (SetBinding) : les barres du jeu sur
    leurs commandes habituelles (ACTIONBUTTON1...), la page 2 de la barre
    principale sur le bouton lui-meme. L infobulle nomme le bouton comme le
    panneau des barres (bindLabel : "Barre du bas 2 - 5"...).
    Interdit en combat (le jeu bloque les changements de raccourcis).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local bindables = {}     -- bouton -> commande
local overlay, panel, target

function ns.RegisterBindable(b, command)
    bindables[b] = command
end

local IGNORED = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
                  UNKNOWN = true, LMETA = true, RMETA = true }
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function withModifiers(key)
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
end

local function showTip()
    if not target then return end
    local cmd = bindables[target]
    local t = ns.Tooltip(overlay, "ANCHOR_TOP")
    t:AddLine(target.bindLabel or (_G["BINDING_NAME_" .. cmd]) or cmd, 1, 0.82, 0)
    local keys = { GetBindingKey(cmd) }
    if #keys == 0 then
        t:AddLine(L.KB_NONE, 0.6, 0.6, 0.6)
    else
        t:AddLine(table.concat(keys, ", "), 1, 1, 1)
    end
    t:AddLine(L.KB_TIP, 0.6, 0.6, 0.6)
    t:Show()
end

local function bind(key)
    if not target or InCombatLockdown() then return end
    local cmd = bindables[target]
    -- la touche quitte son ancienne action et va a ce bouton
    SetBinding(key, cmd)
    showTip()
end

local function clear()
    if not target or InCombatLockdown() then return end
    for _, key in ipairs({ GetBindingKey(bindables[target]) }) do SetBinding(key) end
    showTip()
end

local function build()
    overlay = CreateFrame("Button", "CorpUIQuickBindOverlay", UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:EnableKeyboard(true)
    overlay:EnableMouseWheel(true)
    local tex = overlay:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    local C = ns.COLORS
    tex:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.35)
    overlay:Hide()
    overlay:SetScript("OnLeave", function(self)
        self:Hide()
        target = nil
        ns.HideTooltip()
    end)
    overlay:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then clear() return end
        if IGNORED[key] then return end
        bind(withModifiers(key))
    end)
    overlay:SetScript("OnMouseWheel", function(_, d)
        bind(withModifiers(d > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
    end)
    overlay:SetScript("OnMouseDown", function(_, button)
        if MOUSE[button] then bind(withModifiers(MOUSE[button])) end
    end)

    panel = CreateFrame("Frame", "CorpUIQuickBindPanel", UIParent, "BackdropTemplate")
    panel:SetSize(380, 112)
    panel:SetPoint("TOP", 0, -140)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    ns.UI.SetBackdrop(panel, 0.96)
    ns.UI.Shadow(panel, 4)
    local title = panel:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 15)
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    title:SetText(L.KB_TITLE)
    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    help:SetWidth(356)
    help:SetJustifyH("LEFT")
    help:SetText(L.KB_HELP)
    local save = ns.UI.Button(panel, L.KB_SAVE, 110, function() ns.QuickBind(false, true) end)
    save:SetPoint("BOTTOMRIGHT", -12, 10)
    local cancel = ns.UI.Button(panel, L.KB_CANCEL, 90, function() ns.QuickBind(false, false) end)
    cancel:SetPoint("RIGHT", save, "LEFT", -6, 0)
    panel:Hide()
end

-- appele par le OnEnter des boutons : true si le mode a pris la main
function ns.QuickBindHover(b)
    if not ns.quickBinding or not bindables[b] or InCombatLockdown() then return false end
    target = b
    overlay:ClearAllPoints()
    overlay:SetAllPoints(b)
    overlay:Show()
    showTip()
    return true
end

-- on : activer / terminer ; keep (en terminant) : enregistrer ou annuler
function ns.QuickBind(on, keep)
    if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
    if not overlay then build() end
    if on then
        ns.quickBinding = true
        panel:Show()
        if _G.CorpUIMain then _G.CorpUIMain:Hide() end
        ns.Changed()
        return
    end
    if not ns.quickBinding then return end
    ns.quickBinding = false
    overlay:Hide()
    target = nil
    panel:Hide()
    local set = GetCurrentBindingSet()
    if keep then
        SaveBindings(set)
        ns.Say(L.KB_SAVED)
    else
        LoadBindings(set)
        ns.Say(L.KB_CANCELED)
    end
    ns.Changed()
end

-- entree en combat : on enregistre et on sort du mode
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function()
    if ns.ModuleOff("barres", ev) then return end
    if ns.quickBinding and overlay then
        ns.quickBinding = false
        overlay:Hide()
        panel:Hide()
        target = nil
        SaveBindings(GetCurrentBindingSet())
    end
end)
