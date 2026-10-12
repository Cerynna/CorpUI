--[[--------------------------------------------------------------------------
    CorpUI - page Modules : allumer ou couper chaque module

    Une ligne par module (nom, a quoi il sert, interrupteur), rangee comme
    la colonne des pages. Le choix est enregistre dans CorpUIDB.modules
    (cle = commande du module, false = coupe ; suit les profils) et vaut au
    prochain rechargement : un module ne se defait pas a chaud (cadres
    securises, interface du jeu masquee...). Le socle (Core.lua :
    ns.ModuleOn / ns.ModuleOff) ne laisse rien construire a un module coupe
    et retire sa page et sa commande.
    Commandes rangees avec un autre module (Core.lua, MODULE_OF) : compta
    avec l HV, degats avec le compteur, reactifs avec le marchand, menus
    avec les barres, les mini-jeux ensemble.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local LIST = {
    { cat = "CAT_INTERFACE" },
    { key = "cadres", label = "MODULES_UNITS", desc = "MODULES_UNITS_DESC" },
    { key = "groupe" }, { key = "incantations" }, { key = "auras" }, { key = "chasseur" }, { key = "barres" },
    { key = "xp" },
    { key = "minicarte" }, { key = "infos" }, { key = "quetes" }, { key = "plaques" }, { key = "infobulles" },
    { key = "chat" }, { key = "compteur" }, { key = "sacs" }, { key = "butin" }, { key = "fil" },
    { key = "marchand" }, { key = "habillage" },
    { cat = "CAT_RAID" },
    { key = "buffs" }, { key = "dissipation" }, { key = "rappels" }, { key = "cd" }, { key = "note" },
    { key = "raid" }, { key = "inv" }, { key = "clics" },
    { cat = "CAT_TOOLS" },
    { key = "persos" }, { key = "metiers" }, { key = "hv" }, { key = "dez" }, { key = "talents" },
    { key = "sorts" }, { key = "erreurs" }, { key = "jeux", label = "PAGE_GAMES", desc = "MODULES_GAMES_DESC" }, { key = "podometre" },
}

local ROW_H = 36
local win, status, rows

local function moduleOf(key)
    for _, m in ipairs(ns.modules) do
        if m.command == key then return m end
    end
end

local function textOf(e)
    local m = moduleOf(e.key)
    local title = e.label and L[e.label] or (m and m.title and m.title()) or e.key
    local desc = e.desc and L[e.desc] or (m and m.desc and m.desc()) or ""
    if desc ~= "" then desc = desc:sub(1, 1):upper() .. desc:sub(2) end
    return title, desc
end

local function pending()
    local n = 0
    for _, e in ipairs(LIST) do
        if e.key and ns.ModuleWanted(e.key) ~= ns.ModuleOn(e.key) then n = n + 1 end
    end
    return n
end

local function refresh()
    if not rows then return end
    for _, r in ipairs(rows) do
        local want = ns.ModuleWanted(r.key)
        r.switch:SetChecked(want)
        local c = want and C.text or { 0.5, 0.5, 0.53 }
        r.title:SetTextColor(c[1], c[2], c[3])
        r.tag:SetShown(want ~= ns.ModuleOn(r.key))
    end
    local n = pending()
    if n > 0 then
        status:SetText(string.format(L.MODULES_PENDING, n))
        status:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    else
        status:SetText(L.MODULES_NONE)
        status:SetTextColor(0.55, 0.55, 0.58)
    end
end

local function addRow(e, y)
    local r = CreateFrame("Button", nil, win)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", win, "TOPLEFT", 4, y)
    r:SetPoint("RIGHT", win, "RIGHT", -4, 0)
    r.key = e.key
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    local title, desc = textOf(e)
    r.switch = ns.UI.Switch(r, nil, function(v)
        ns.SetModuleWanted(e.key, v)
        refresh()
    end)
    r.switch:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -4)
    r.title:SetJustifyH("LEFT")
    r.title:SetText(title)
    r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.tag:SetPoint("LEFT", r.title, "RIGHT", 8, 0)
    r.tag:SetText(L.MODULES_TAG)
    r.tag:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    r.desc = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.desc:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -20)
    r.desc:SetPoint("RIGHT", r.switch, "LEFT", -12, 0)
    r.desc:SetJustifyH("LEFT")
    r.desc:SetWordWrap(false)
    r.desc:SetText(desc)
    -- toute la ligne bascule l interrupteur
    r:SetScript("OnClick", function() r.switch:Click() end)
    table.insert(rows, r)
end

local function build()
    win = ns.NewPanel("CorpUIModules", L.PAGE_MODULES, 440, 400)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -38)
    hint:SetPoint("RIGHT", win, "RIGHT", -8, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.MODULES_HINT)
    -- bouton securise (ReloadUI est refuse aux addons) : ancre sur le panneau
    local reload = ns.UI.ReloadButton(win, L.GEN_RELOAD, 160)
    reload:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -76)
    status = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("LEFT", win, "TOPLEFT", 8, -87)
    status:SetPoint("RIGHT", reload, "LEFT", -10, 0)
    status:SetJustifyH("LEFT")
    rows = {}
    local y = -110
    for _, e in ipairs(LIST) do
        if e.cat then
            local h = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            h:SetPoint("TOPLEFT", win, "TOPLEFT", 8, y - 6)
            h:SetText(L[e.cat])
            local line = win:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            ns.NoSnap(line)
            line:SetPoint("TOPLEFT", win, "TOPLEFT", 8, y - 24)
            line:SetPoint("RIGHT", win, "RIGHT", -8, 0)
            line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.3)
            y = y - 30
        else
            addRow(e, y)
            y = y - ROW_H
        end
    end
    win:SetHeight(math.floor(-y + 10))
    win:SetScript("OnShow", refresh)
    refresh()
end

local function open()
    if not win then build() end
    ns.ShowPanel(win)
end

-- Grille compacte des interrupteurs (assistant d installation) : intertitres
-- et modules en colonnes (remplies de haut en bas), nom seul, a quoi il
-- sert dans l infobulle. Renvoie le cadre (hauteur faite) ; :Refresh().
local CELL_H = 20
function ns.ModuleSwitchGrid(parent, width, cols)
    local g = CreateFrame("Frame", nil, parent)
    local per = math.ceil(#LIST / cols)
    local colW = math.floor(width / cols)
    g:SetSize(width, per * CELL_H)
    local switches = {}
    for i, e in ipairs(LIST) do
        local col, row = math.floor((i - 1) / per), (i - 1) % per
        local x, y = col * colW, -row * CELL_H
        if e.cat then
            local h = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            h:SetPoint("TOPLEFT", g, "TOPLEFT", x, y - 5)
            h:SetText(L[e.cat])
        else
            local title, desc = textOf(e)
            local s = ns.UI.Switch(g, nil, function(v) ns.SetModuleWanted(e.key, v) end)
            s:SetPoint("TOPLEFT", g, "TOPLEFT", x, y - 2)
            local fs = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", s, "RIGHT", 6, 0)
            fs:SetWidth(colW - 42)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            fs:SetText(title)
            s:SetHitRectInsets(0, -(colW - 40), -2, -2)
            s:HookScript("OnEnter", function(self)
                local tip = ns.Tooltip(self, "ANCHOR_RIGHT")
                tip:AddLine(title)
                if desc ~= "" then tip:AddLine(desc, 1, 1, 1, true) end
                tip:Show()
            end)
            s:HookScript("OnLeave", ns.HideTooltip)
            s.key = e.key
            table.insert(switches, s)
        end
    end
    function g:Refresh()
        for _, s in ipairs(switches) do s:SetChecked(ns.ModuleWanted(s.key)) end
    end
    g:Refresh()
    return g
end

ns.RegisterModule({
    command = "modules",
    panelName = "CorpUIModules",
    icon = "Interface\\Icons\\Trade_Engineering",
    title = function() return L.PAGE_MODULES end,
    desc = function() return L.MODULES_DESC end,
    Slash = open,
    Open = open,
})
