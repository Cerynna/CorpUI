--[[--------------------------------------------------------------------------
    CorpUI - module Sorts au clic
    Lancer un sort en cliquant sur un cadre d unite de CorpUI (joueur, cible,
    cible de la cible, familier, focalisation, groupe, raid).

    Nos cadres sont des boutons securises : on leur pose les attributs du
    modele SecureActionButton, par bouton de souris et modificateur
    ("shift-type2" = "spell", "shift-spell2" = "Renouveau(Rang 3)").
    Amical / ennemi : le modele sait rediriger un clic vers un bouton
    "virtuel" selon que l unite peut etre aidee (helpbutton) ou attaquee
    (harmbutton) ; ce bouton virtuel porte alors son propre sort.
    Pas de crochet ni d enveloppe sur du code de Blizzard. Attributs
    securises : poses hors combat seulement.

    Trois couches par case : "toutes" (par defaut), "amicale", "ennemie" ;
    les deux dernieres remplacent la premiere selon l unite cliquee.
    Chaque case recoit un sort (rang exact), ou "cibler" / "menu".
    Reglages par personnage.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local BUTTONS = { 1, 2, 3, 4, 5 }
-- ordre impose par le modele : alt-, ctrl-, shift-
local MODS = { "", "shift-", "ctrl-", "alt-", "ctrl-shift-", "alt-ctrl-", "alt-shift-" }
local MOD_LABEL = { [""] = "CLICK_MOD_NONE", ["shift-"] = "CLICK_MOD_SHIFT", ["ctrl-"] = "CLICK_MOD_CTRL",
    ["alt-"] = "CLICK_MOD_ALT", ["ctrl-shift-"] = "CLICK_MOD_CTRLSHIFT", ["alt-ctrl-"] = "CLICK_MOD_CTRLALT",
    ["alt-shift-"] = "CLICK_MOD_SHIFTALT" }
local LAYERS = { "any", "help", "harm" }
local ACTIONS = { "target", "togglemenu" }     -- ordre de defilement au clic

local db                -- reglages du personnage courant
local pending = false

-- cle d une case : "shift-2", "shift-2|help", "shift-2|harm"
local function key(mod, btn, layer)
    if layer == "any" then return mod .. btn end
    return mod .. btn .. "|" .. layer
end

-- nom de bouton virtuel (lettres et chiffres seulement) : "hs2", "ecs1"...
local function virtual(layer, mod, btn)
    local tag = mod:gsub("alt%-", "a"):gsub("ctrl%-", "c"):gsub("shift%-", "s")
    return (layer == "help" and "h" or "e") .. tag .. btn
end

---------------------------------------------------------------------------
-- Sorts : nom, rang
---------------------------------------------------------------------------

local refreshCells       -- defini plus bas (fenetre)
-- donnees des sorts : true = en chargement, false = chargees (plus jamais
-- redemandees : un sort sans rang n a pas de sous-texte, et le client
-- rappelle tout de suite un sort deja charge -> redessin sans fin)
local loading = {}
local refreshQueued = false
local function queueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if refreshCells then refreshCells() end
    end)
end

-- rang lisible ("Rang 3") : C_Spell d abord (ce client), puis l ancienne API
local function readSubtext(id)
    -- (pas d ipairs : il s arreterait sur la premiere fonction absente)
    local fns = { C_Spell and C_Spell.GetSpellSubtext or false, GetSpellSubtext or false }
    for i = 1, #fns do
        local fn = fns[i]
        if type(fn) == "function" then
            local ok, s = pcall(fn, id)
            if ok and type(s) == "string" and s ~= "" then return s end
        end
    end
end

local function spellInfo(id, stored)
    local name, sub
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok then name = n end
    end
    sub = readSubtext(id)
    if not sub and id and loading[id] == nil and Spell and Spell.CreateFromSpellID then
        -- donnees pas encore chargees : on redessine quand elles arrivent
        loading[id] = true
        pcall(function()
            Spell:CreateFromSpellID(id):ContinueOnSpellLoad(function()
                loading[id] = false
                queueRefresh()      -- jamais dans l appel lui-meme
            end)
        end)
    end
    return name, sub or stored
end

-- texte a lancer : "Soins(Rang 3)" pour viser ce rang precis
local function castText(entry)
    if not entry or entry.action then return nil end
    local name, sub = spellInfo(entry.id, entry.sub)
    name = name or entry.name
    if not name then return nil end
    if sub and sub:find("%d") then return name .. "(" .. sub .. ")" end
    return name
end

local function rankText(entry)
    if not entry or entry.action then return "" end
    local _, sub = spellInfo(entry.id, entry.sub)
    local n = sub and sub:match("%d+")
    return n and string.format(L.CLICK_RANK, n) or ""
end

---------------------------------------------------------------------------
-- Attributs sur les cadres
---------------------------------------------------------------------------

-- pose une entree (sort ou action) sous un nom d attribut donne
local function setEntry(b, typeAttr, spellAttr, e)
    local text = castText(e)
    if text then
        b:SetAttribute(typeAttr, "spell")
        b:SetAttribute(spellAttr, text)
    else
        b:SetAttribute(typeAttr, e and e.action or nil)
        b:SetAttribute(spellAttr, nil)
    end
end

local function applyTo(b)
    if not db then return end
    for _, mod in ipairs(MODS) do
        for _, btn in ipairs(BUTTONS) do
            -- couche "toutes"
            setEntry(b, mod .. "type" .. btn, mod .. "spell" .. btn, db[key(mod, btn, "any")])
            -- couches amicale / ennemie : redirection vers un bouton virtuel
            for _, layer in ipairs({ "help", "harm" }) do
                local e = db[key(mod, btn, layer)]
                local v = virtual(layer, mod, btn)
                local redirect = mod .. (layer == "help" and "helpbutton" or "harmbutton") .. btn
                if e then
                    b:SetAttribute(redirect, v)
                    setEntry(b, "*type-" .. v, "*spell-" .. v, e)
                else
                    b:SetAttribute(redirect, nil)
                    b:SetAttribute("*type-" .. v, nil)
                    b:SetAttribute("*spell-" .. v, nil)
                end
            end
        end
    end
end

local function applyAll()
    if InCombatLockdown() then pending = true return end
    pending = false
    for _, b in ipairs(ns.unitButtons) do applyTo(b) end
end

-- un cadre cree plus tard (raid...) recoit aussitot les reglages
ns.ApplyClickCast = function(b)
    if not db then return end
    if InCombatLockdown() then pending = true return end
    applyTo(b)
end

---------------------------------------------------------------------------
-- Fenetre : couche choisie, grille boutons x modificateurs
---------------------------------------------------------------------------

local win
local cells = {}
local layerTabs = {}
local layer = "any"
local CELL, COLW, ROWH = 34, 58, 40

local function cursorSpell()
    local kind, a, b, c = GetCursorInfo()
    if kind ~= "spell" then return nil end
    local id = c
    if not id and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, a, b)
        if ok and info then id = info.spellID end
    end
    if not id then return nil end
    local name, sub = spellInfo(id)
    -- le grimoire affiche le rang sous le nom : on le lit aussi la
    if not sub and C_SpellBook and C_SpellBook.GetSpellBookItemName then
        local ok, _, s = pcall(C_SpellBook.GetSpellBookItemName, a, b)
        if ok and type(s) == "string" and s ~= "" then sub = s end
    end
    return { id = id, name = name, sub = sub }
end

refreshCells = function()
    if not win then return end
    local C = ns.COLORS
    for _, t in ipairs(layerTabs) do
        local on = t.layer == layer
        t.bg:SetBackdropBorderColor((on and C.gold or C.border)[1], (on and C.gold or C.border)[2], (on and C.gold or C.border)[3], 1)
    end
    for _, cell in ipairs(cells) do
        local e = db and db[key(cell.mod, cell.btn, layer)]
        -- en couche amicale / ennemie, une case vide montre en pale ce que fait "toutes"
        local base = (layer ~= "any" and not e) and db and db[key(cell.mod, cell.btn, "any")]
        local shown = e or base
        cell.icon:SetAlpha(e and 1 or 0.3)
        cell.label:SetAlpha(e and 1 or 0.4)
        cell.rank:SetText(rankText(shown))
        cell.rank:SetAlpha(e and 1 or 0.4)
        if shown and shown.action then
            cell.icon:SetTexture(nil)
            cell.label:SetText(shown.action == "target" and L.CLICK_TARGET or L.CLICK_MENU)
            cell.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        elseif shown then
            local ok, tex = pcall(C_Spell.GetSpellTexture, shown.id)
            cell.icon:SetTexture(ok and tex or "Interface\\Icons\\INV_Misc_QuestionMark")
            cell.label:SetText("")
        else
            cell.icon:SetTexture(nil)
            cell.label:SetText("")
        end
    end
end

local function assign(cell, entry)
    db[key(cell.mod, cell.btn, layer)] = entry
    refreshCells()
    applyAll()
    if InCombatLockdown() then ns.Say(L.CLICK_AFTER_COMBAT) end
end

local function buildWindow()
    win = ns.UI.Window("CorpUIClickCastOptions", ns.TITLE .. " - " .. L.MOD_CLICK, nil, 440, 470)
    local C = ns.COLORS
    local left, top = 92, -88

    -- couches : toutes / amicale / ennemie
    for i, ly in ipairs(LAYERS) do
        local t = ns.UI.Button(win, L["CLICK_LAYER_" .. string.upper(ly)], 110, function()
            layer = ly
            refreshCells()
        end)
        t:SetPoint("TOPLEFT", 8 + (i - 1) * 118, -34)
        t.layer = ly
        -- liseré : le bouton plat de CorpUI est son propre fond
        t.bg = t
        -- apres le survol, le bouton reprend son liseré : on remet l or
        t:HookScript("OnLeave", function() refreshCells() end)
        table.insert(layerTabs, t)
    end

    -- en-tetes : boutons de la souris
    for i, btn in ipairs(BUTTONS) do
        local h = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("BOTTOM", win, "TOPLEFT", left + (i - 1) * COLW + CELL / 2, top + 4)
        h:SetText(L["CLICK_BTN" .. btn])
    end
    for r, mod in ipairs(MODS) do
        local rl = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rl:SetPoint("RIGHT", win, "TOPLEFT", left - 8, top - (r - 1) * ROWH - CELL / 2)
        rl:SetText(L[MOD_LABEL[mod]])
        for i, btn in ipairs(BUTTONS) do
            local cell = CreateFrame("Button", nil, win)
            cell:SetSize(CELL, CELL)
            cell:SetPoint("TOPLEFT", left + (i - 1) * COLW, top - (r - 1) * ROWH)
            ns.UI.Skin(cell, 0.9)
            cell.icon = cell:CreateTexture(nil, "ARTWORK")
            cell.icon:SetPoint("TOPLEFT", 1, -1)
            cell.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            cell.label:SetPoint("CENTER")
            cell.label:SetWidth(CELL + 20)
            -- rang du sort, en bas a droite de l icone
            cell.rank = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            cell.rank:SetPoint("BOTTOMRIGHT", 1, 1)
            cell.rank:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
            local hl = cell:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 0.25)
            cell.mod, cell.btn = mod, btn
            cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local function drop(self)
                local s = cursorSpell()
                if s then
                    ClearCursor()
                    assign(self, s)
                end
            end
            cell:SetScript("OnReceiveDrag", drop)
            cell:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    assign(self, nil)
                elseif cursorSpell() then
                    drop(self)
                else
                    -- vide -> cibler -> menu -> vide
                    local e = db[key(self.mod, self.btn, layer)]
                    local nextAction
                    if not e or not e.action then
                        nextAction = ACTIONS[1]
                    else
                        for j, a in ipairs(ACTIONS) do
                            if a == e.action then nextAction = ACTIONS[j + 1] break end
                        end
                    end
                    assign(self, nextAction and { action = nextAction } or nil)
                end
            end)
            cell:SetScript("OnEnter", function(self)
                local t = ns.Tooltip(self, "ANCHOR_RIGHT")
                local e = db and db[key(self.mod, self.btn, layer)]
                t:AddLine(rl:GetText() .. " + " .. L["CLICK_BTN" .. btn] .. "  (" .. L["CLICK_LAYER_" .. string.upper(layer)] .. ")")
                if e and e.action then
                    t:AddLine(e.action == "target" and L.CLICK_TARGET or L.CLICK_MENU, 1, 1, 1)
                elseif e then
                    local name, sub = spellInfo(e.id, e.sub)
                    t:AddLine((name or e.name or "?") .. (sub and ("  |cffaaaaaa" .. sub .. "|r") or ""), 1, 1, 1)
                elseif layer ~= "any" then
                    t:AddLine(L.CLICK_FALLBACK, 0.7, 0.7, 0.7)
                end
                t:AddLine(L.CLICK_DROP, 0.8, 0.8, 0.8)
                t:AddLine(L.CLICK_CYCLE, 0.8, 0.8, 0.8)
                if e then t:AddLine(L.CLICK_CLEAR, 0.6, 0.6, 0.6) end
                t:Show()
            end)
            cell:SetScript("OnLeave", ns.HideTooltip)
            table.insert(cells, cell)
        end
    end
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 8, top - #MODS * ROWH - 4)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.CLICK_HINT)
    win:HookScript("OnShow", refreshCells)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("clics", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.clickcast = root.clickcast or {}
        local k = ns.CharKey()
        root.clickcast[k] = root.clickcast[k] or {}
        db = root.clickcast[k]
        -- depart : clic gauche = cibler, clic droit = menu (une fois)
        if not db._init then
            if db["1"] == nil then db["1"] = { action = "target" } end
            if db["2"] == nil then db["2"] = { action = "togglemenu" } end
            db._init = true
        end
        applyAll()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then applyAll() end
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        if db then applyAll() end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "clics",
    alias = "clickcast",
    panelName = "CorpUIClickCastOptions",
    icon = "Interface\\Icons\\Spell_Holy_Renew",
    title = function() return L.MOD_CLICK end,
    desc = function() return L.CLICK_DESC end,
    Slash = function(input)
        if input and input:find("diag") then
            -- attributs reellement poses sur le cadre joueur
            local f = _G.CorpUIPlayerFrame
            if not f then return end
            for _, n in ipairs({ "type1", "shift-type1", "shift-spell1", "*type1", "helpbutton1", "harmbutton1",
                                 "shift-helpbutton1", "shift-harmbutton1", "type2", "shift-type2", "unit" }) do
                ns.Chat("  " .. n .. " = " .. tostring(f:GetAttribute(n)))
            end
            ns.Chat("  boutons inscrits : " .. #ns.unitButtons)
            return
        end
        toggle()
    end,
    Open = toggle,
})
