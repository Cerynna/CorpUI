--[[--------------------------------------------------------------------------
    CorpUI - assistant d installation
    Les etapes dependent du cas :
      - premier lancement (ns.root.installed absent) : langue, modules,
        couleur, police, fin ;
      - personnage qui decouvre CorpUI (10/10 : ns.NEW_CHAR, note dans
        root.setupPending jusqu a la fin de l assistant, meme apres une
        deconnexion) : profil (partager un profil, ou en creer un pour lui :
        copie ou reglages par defaut), modules, couleur, police, fin ;
      - relance (onglet General, /corp assistant) : toutes.
    Le profil change tout de suite (ns.ProfileAdopt / ProfileCreate) : les
    etapes suivantes s ecrivent dans le bon profil ; la fin recharge
    l interface. Tout se reglant aussi dans la fenetre CorpUI, on peut
    passer l assistant.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local W, H, HEAD_H = 560, 480, 50
local frame, steps, index = nil, {}, 1
local order = {}            -- etapes de cette ouverture (selon le cas)
local byKey = {}            -- cle -> etape
local mode                  -- "first", "newchar" ou "manual"
local stepText, prevBtn, nextBtn

local function body(titleKey, textKey)
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 24, -HEAD_H - 34)
    p:SetPoint("BOTTOMRIGHT", -24, 52)
    local t = p:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(t, 17)
    t:SetPoint("TOPLEFT")
    t:SetTextColor(ns.COLORS.gold[1], ns.COLORS.gold[2], ns.COLORS.gold[3])
    t:SetText(L[titleKey])
    local d = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -10)
    d:SetWidth(W - 48)
    d:SetJustifyH("LEFT")
    d:SetSpacing(2)
    d:SetText(L[textKey])
    p.text = d
    p:Hide()
    p.title = t
    table.insert(steps, p)
    return p
end

local function show(i)
    index = math.max(1, math.min(#order, i))
    for _, p in ipairs(steps) do p:SetShown(p == order[index]) end
    stepText:SetText(string.format(L.INST_STEP, index, #order))
    prevBtn:SetShown(index > 1)
    nextBtn:SetText(index == #order and L.INST_FINISH or L.INST_NEXT)
    if order[index].refresh then order[index].refresh() end
end

-- fin (ou "Passer") : CorpUI installe, ce personnage aussi
local function finish()
    ns.root.installed = true
    if type(ns.root.setupPending) == "table" then ns.root.setupPending[ns.CharKey()] = nil end
    frame:Hide()
end

-- petite case de choix exclusif (etape Profil)
local function radio(parent, onClick)
    local C = ns.COLORS
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    local ring = b:CreateTexture(nil, "BORDER")
    ring:SetAllPoints()
    ring:SetColorTexture(0, 0, 0, 1)
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(0.13, 0.135, 0.16, 1)
    local dot = b:CreateTexture(nil, "OVERLAY")
    dot:SetPoint("TOPLEFT", 4, -4)
    dot:SetPoint("BOTTOMRIGHT", -4, 4)
    dot:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 1)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("LEFT", b, "RIGHT", 8, 0)
    b:SetScript("OnEnter", function() ring:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1) end)
    b:SetScript("OnLeave", function() ring:SetColorTexture(0, 0, 0, 1) end)
    b:SetScript("OnClick", onClick)
    function b:SetOn(on) dot:SetShown(on) end
    function b:SetLabel(t)
        self.label:SetText(t)
        self:SetHitRectInsets(0, -(self.label:GetStringWidth() + 12), -3, -3)
    end
    return b
end

local function build()
    local C = ns.COLORS
    frame = CreateFrame("Frame", "CorpUIInstall", UIParent, "BackdropTemplate")
    frame:SetSize(W, H)
    frame:SetPoint("CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    ns.UI.SetBackdrop(frame, 0.97)
    ns.UI.Shadow(frame, 5)

    -- meme habit que la fenetre CorpUI : bandeau du titre sombre et uni
    local head = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(HEAD_H - 6)
    head:SetColorTexture(0, 0, 0, 0.275)
    local logo = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    logo:SetSize(38, 38)
    logo:SetPoint("TOPLEFT", 8, -3)
    logo:SetTexture(ns.MEDIA .. "logo128")
    local title = frame:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 20)
    title:SetPoint("LEFT", logo, "RIGHT", 6, 1)
    title:SetText(L.INST_TITLE)
    stepText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    stepText:SetPoint("TOPRIGHT", -16, -18)

    -- 1. langue
    local s1 = body("INST_WELCOME_T", "INST_WELCOME")
    byKey.lang = s1
    local langs = { { short = "auto", name = L.GEN_AUTO } }
    for _, l in ipairs(ns.LANGUAGES) do table.insert(langs, l) end
    s1.buttons = {}
    for i, lang in ipairs(langs) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local b = ns.UI.Button(s1, lang.name, 150, function()
            ns.LangCommand(lang.short)
            s1.refresh()
        end)
        b:SetWidth(156)
        b:SetPoint("TOPLEFT", s1.text, "BOTTOMLEFT", col * 162, -14 - row * 26)
        b.code, b.langName = lang.code, lang.name
        s1.buttons[i] = b
    end
    s1.refresh = function()
        for _, b in ipairs(s1.buttons) do
            local on = (b.code == nil and ns.root.lang == nil) or (b.code ~= nil and b.code == ns.root.lang)
            b:SetText(on and ("|cffffd140» " .. b.langName .. " «|r") or b.langName)
        end
    end

    -- 2. couleur
    local s2 = body("INST_THEME_T", "INST_THEME")
    byKey.theme = s2
    s2.swatches = {}
    for i, t in ipairs(ns.THEMES) do
        local s = CreateFrame("Button", nil, s2)
        s:SetSize(40, 26)
        s:SetPoint("TOPLEFT", s2.text, "BOTTOMLEFT", 20 + (i - 1) % 5 * 96, -16 - math.floor((i - 1) / 5) * 62)
        s.ring = s:CreateTexture(nil, "BACKGROUND")
        s.ring:SetPoint("TOPLEFT", -2, 2)
        s.ring:SetPoint("BOTTOMRIGHT", 2, -2)
        s.ring:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        local edge = s:CreateTexture(nil, "BORDER")
        edge:SetAllPoints()
        edge:SetColorTexture(0, 0, 0, 1)
        local c = ns.ThemeColor(t.key)
        local fill = s:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        if t.bg then
            ns.UI.Gradient(fill, "VERTICAL", 0.02, 0.02, 0.022, 1, 0.30, 0.30, 0.33, 1)
        else
            ns.UI.Gradient(fill, "VERTICAL", c[1] * 0.45, c[2] * 0.45, c[3] * 0.45, 1, c[1], c[2], c[3], 1)
        end
        s.name = s2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.name:SetPoint("TOP", s, "BOTTOM", 0, -4)
        s.name:SetWidth(92)
        s.name:SetJustifyH("CENTER")
        s.name:SetText(L["THEME_" .. string.upper(t.key)])
        s.key = t.key
        s:SetScript("OnClick", function()
            ns.root.theme = t.key
            s2.refresh()
        end)
        s2.swatches[i] = s
    end
    s2.refresh = function()
        local chosen = ns.root.theme or "violet"
        for _, s in ipairs(s2.swatches) do s.ring:SetShown(s.key == chosen) end
    end

    -- 3. police (meme reglage que l onglet General)
    local s3 = body("INST_FONT_T", "INST_FONT")
    byKey.font = s3
    if ns.BuildFontOptions then ns.BuildFontOptions(s3, s3.text) end

    -- 4. profil : partager un profil, ou en creer un pour ce personnage
    -- (copie du profil choisi, ou reglages par defaut). Applique a "Suivant".
    local s4 = body("INST_PROFILE_T", "INST_PROFILE")
    byKey.profile = s4
    local plabel = s4:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    plabel:SetText(L.INST_PROF_BASE)
    local base, choice, created
    local picker = ns.UI.Select(s4, 200, function()
        local list = {}
        for _, n in ipairs(ns.ProfileNames()) do
            if n ~= created then table.insert(list, { value = n, text = ns.ProfileLabel(n) }) end
        end
        return list
    end, function() return base end, function(v) base = v s4.refresh() end)
    picker:SetPoint("TOPLEFT", s4.text, "BOTTOMLEFT", 70, -16)
    plabel:SetPoint("RIGHT", picker, "LEFT", -8, 0)
    local users = s4:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    users:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 0, -4)
    users:SetWidth(W - 130)
    users:SetJustifyH("LEFT")
    users:SetWordWrap(false)
    local radios = {}
    for i, key in ipairs({ "use", "copy", "fresh" }) do
        local r = radio(s4, function() choice = key s4.refresh() end)
        r:SetPoint("TOPLEFT", s4.text, "BOTTOMLEFT", 4, -66 - (i - 1) * 28)
        r.key = key
        radios[i] = r
    end
    s4.refresh = function()
        base = base or (ns.CharProfile and ns.CharProfile()) or "Default"
        choice = choice or "use"
        local me = UnitName("player") or "?"
        if mode == "newchar" then
            s4.title:SetText(L.INST_NEWCHAR_T)
            s4.text:SetText(string.format(L.INST_NEWCHAR, me))
        else
            s4.title:SetText(L.INST_PROFILE_T)
            s4.text:SetText(L.INST_PROFILE)
        end
        picker:Refresh()
        local who = ns.ProfileUsers and ns.ProfileUsers(base) or {}
        users:SetText(#who > 0 and string.format(L.PROF_USED_BY, table.concat(who, ", ")) or "")
        local newName = created or me
        radios[1]:SetLabel(L.INST_PROF_USE)
        radios[2]:SetLabel(string.format(L.INST_PROF_COPY, newName))
        radios[3]:SetLabel(string.format(L.INST_PROF_FRESH, newName))
        for _, r in ipairs(radios) do r:SetOn(r.key == choice) end
    end
    -- au passage a l etape suivante
    s4.apply = function()
        if choice == "use" then
            ns.ProfileAdopt(base)
        else
            created = ns.ProfileCreate(choice == "copy" and base or nil, choice == "fresh", created)
        end
    end

    -- modules : les interrupteurs de la page Modules, en grille
    local s5 = body("INST_MODULES_T", "INST_MODULES")
    byKey.modules = s5
    local grid
    s5.refresh = function()
        if not grid and ns.ModuleSwitchGrid then
            grid = ns.ModuleSwitchGrid(s5, W - 48, 3)
            grid:SetPoint("TOPLEFT", s5.text, "BOTTOMLEFT", 0, -10)
        end
        if grid then grid:Refresh() end
    end

    -- fin
    byKey.done = body("INST_DONE_T", "INST_DONE")

    -- pied : passer, precedent, suivant / terminer
    local skip = ns.UI.Button(frame, L.INST_SKIP, 110, finish)
    skip:SetPoint("BOTTOMLEFT", 16, 14)
    -- suivant ; a la derniere etape : rechargement (bouton securise)
    nextBtn = ns.UI.ReloadButton(frame, L.INST_NEXT, 170, function()
        if index < #order then
            local cur = order[index]
            if cur.apply then cur.apply() end
            show(index + 1)
            return false
        end
        finish()
    end)
    nextBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    prevBtn = ns.UI.Button(frame, L.INST_PREV, 110, function() show(index - 1) end)
    prevBtn:SetPoint("RIGHT", nextBtn, "LEFT", -6, 0)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    ns.NoSnap(line)
    line:SetPoint("BOTTOMLEFT", 12, 46)
    line:SetPoint("BOTTOMRIGHT", -12, 46)
    ns.UI.Gradient(line, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0, C.violet[1], C.violet[2], C.violet[3], 0.6)
end

-- etapes selon le cas
local ORDERS = {
    first = { "lang", "modules", "theme", "font", "done" },
    newchar = { "profile", "modules", "theme", "font", "done" },
    manual = { "lang", "profile", "modules", "theme", "font", "done" },
}

-- m : "first", "newchar" ou "manual" (defaut)
function ns.OpenInstall(m)
    if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
    if not frame then build() end
    mode = ORDERS[m] and m or "manual"
    wipe(order)
    for _, k in ipairs(ORDERS[mode]) do table.insert(order, byKey[k]) end
    if _G.CorpUIMain then _G.CorpUIMain:Hide() end
    frame:Show()
    show(1)
end

-- a la connexion : premier lancement, ou personnage qui decouvre CorpUI
-- (en combat : a la sortie du combat)
local ev = CreateFrame("Frame")
local wanted
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
    ev:UnregisterAllEvents()
    if event == "PLAYER_REGEN_ENABLED" then
        if wanted then ns.OpenInstall(wanted) end
        return
    end
    local root = ns.root
    if not root then return end
    local key = ns.CharKey()
    if ns.NEW_CHAR and root.installed then
        if type(root.setupPending) ~= "table" then root.setupPending = {} end
        root.setupPending[key] = true
    end
    if not root.installed then
        wanted = "first"
    elseif type(root.setupPending) == "table" and root.setupPending[key] then
        wanted = "newchar"
    end
    if not wanted then return end
    C_Timer.After(2, function()
        if InCombatLockdown() then
            pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
        else
            ns.OpenInstall(wanted)
        end
    end)
end)

-- /corp assistant (pas d onglet : ni Open ni panneau)
ns.RegisterModule({
    command = "assistant",
    alias = "install",
    desc = function() return L.INST_TITLE end,
    Slash = function() ns.OpenInstall("manual") end,
})
