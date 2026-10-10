--[[--------------------------------------------------------------------------
    CorpUI - assistant d installation
    Au premier lancement (ns.root.installed absent) : une fenetre en cinq
    etapes - langue, couleur, police, profil, fin. Tout se reglant aussi
    dans la fenetre CorpUI, on peut passer l assistant. Il se relance depuis
    l onglet General ou par /corp assistant.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local W, H, HEAD_H = 540, 380, 50
local frame, steps, index = nil, {}, 1
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
    table.insert(steps, p)
    return p
end

local function show(i)
    index = math.max(1, math.min(#steps, i))
    for k, p in ipairs(steps) do p:SetShown(k == index) end
    stepText:SetText(string.format(L.INST_STEP, index, #steps))
    prevBtn:SetShown(index > 1)
    nextBtn:SetText(index == #steps and L.INST_FINISH or L.INST_NEXT)
    if steps[index].refresh then steps[index].refresh() end
end

local function finish()
    ns.root.installed = true
    frame:Hide()
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
    if ns.BuildFontOptions then ns.BuildFontOptions(s3, s3.text) end

    -- 4. profil
    local s4 = body("INST_PROFILE_T", "INST_PROFILE")
    local pname = s4:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    local chosen
    local function stepProfile(d)
        local list = ns.ProfileNames()
        local idx = 1
        for i, n in ipairs(list) do if n == chosen then idx = i end end
        chosen = list[(idx - 1 + d) % #list + 1]
        ns.SetCharProfile(chosen)
        s4.refresh()
    end
    local pp = ns.UI.Button(s4, "<", 26, function() stepProfile(-1) end)
    pp:SetSize(26, 24)
    pp:SetPoint("TOPLEFT", s4.text, "BOTTOMLEFT", 0, -16)
    pname:SetPoint("LEFT", pp, "RIGHT", 10, 0)
    pname:SetWidth(180)
    local pn = ns.UI.Button(s4, ">", 26, function() stepProfile(1) end)
    pn:SetSize(26, 24)
    pn:SetPoint("LEFT", pp, "RIGHT", 200, 0)
    s4.refresh = function()
        chosen = chosen or (ns.CharProfile and ns.CharProfile()) or "Default"
        pname:SetText(ns.ProfileLabel and ns.ProfileLabel(chosen) or chosen)
        pname:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    end

    -- 5. fin
    body("INST_DONE_T", "INST_DONE")

    -- pied : passer, precedent, suivant / terminer
    local skip = ns.UI.Button(frame, L.INST_SKIP, 110, finish)
    skip:SetPoint("BOTTOMLEFT", 16, 14)
    -- suivant ; a la derniere etape : rechargement (bouton securise)
    nextBtn = ns.UI.ReloadButton(frame, L.INST_NEXT, 170, function()
        if index < #steps then
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

function ns.OpenInstall()
    if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
    if not frame then build() end
    if _G.CorpUIMain then _G.CorpUIMain:Hide() end
    frame:Show()
    show(1)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    ev:UnregisterAllEvents()
    if ns.root and not ns.root.installed then
        C_Timer.After(2, function()
            if not InCombatLockdown() then ns.OpenInstall() end
        end)
    end
end)

-- /corp assistant (pas d onglet : ni Open ni panneau)
ns.RegisterModule({
    command = "assistant",
    alias = "install",
    desc = function() return L.INST_TITLE end,
    Slash = function() ns.OpenInstall() end,
})
