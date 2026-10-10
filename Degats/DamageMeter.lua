--[[--------------------------------------------------------------------------
    CorpUI - module Compteur de degats
    Style CorpUI pour le compteur de degats de Blizzard (fenetres
    DamageMeterSessionWindowN) :
      - panneau du theme, bandeau d accent et filet d or sous l en-tete ;
      - lignes en barres lisses CorpUI (texture de barre commune), sans
        l ombre de Blizzard.
    Apparence seulement : aucune valeur n est lue (elles peuvent etre
    secretes en combat), aucun code de Blizzard n est appele. Les lignes,
    creees au fil du combat, sont habillees par un releve leger.
    Pas de panneau a lui : sa case est dans le panneau Compteur.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local HEADER = 32
local db
local windows = {}       -- fenetre -> notre panneau
local entries = {}       -- ligne deja habillee

local function clear(t)
    if not t then return end
    pcall(t.SetAtlas, t, nil)
    pcall(t.SetTexture, t, nil)
    pcall(t.SetAlpha, t, 0)
end

local function key(obj, k)
    local ok, v = pcall(function() return obj[k] end)
    if ok then return v end
end

local function skinEntry(e)
    if entries[e] then return end
    entries[e] = true
    local sb = key(e, "StatusBar")
    if type(sb) ~= "table" or not sb.SetStatusBarTexture then return end
    pcall(sb.SetStatusBarTexture, sb, ns.BAR_TEXTURE)
    clear(key(sb, "Background"))
    clear(key(sb, "BackgroundEdge"))
    -- fond sombre et liseré fin sous la barre
    local bg = sb:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)
    local icon = key(e, "Icon")
    local tex = icon and key(icon, "Icon")
    if tex and tex.SetTexCoord then pcall(tex.SetTexCoord, tex, 0.08, 0.92, 0.08, 0.92) end
end

---------------------------------------------------------------------------
-- Boutons de l en-tete (type, session, reglages, reduire) : leurs dessins
-- passent en transparence (le code de Blizzard qui change leur atlas
-- selon l etat ne touche pas a l alpha) ; on dessine sur le bouton lui-meme
-- un carre CorpUI : fond obsidienne, liseré, survol a l accent, icone d or.
---------------------------------------------------------------------------

local ours = {}          -- nos textures (a ne pas masquer)
local buttons = {}       -- bouton -> nos elements
local btnErr             -- erreur signalee une fois

local function hideArt(b)
    for _, r in ipairs({ b:GetRegions() }) do
        if not ours[r] and r.GetObjectType and r:GetObjectType() == "Texture" then pcall(r.SetAlpha, r, 0) end
    end
end

local function tex(b, layer, sub)
    local t = b:CreateTexture(nil, layer, nil, sub)
    ours[t] = true
    ns.NoSnap(t)   -- traits fins toujours dessines (Core.lua)
    return t
end

local BOX = 18           -- tous les carres de l en-tete : meme taille

-- carre centre sur anchor (ou le bouton) horizontalement ; la hauteur est
-- recalee par align() sur le milieu de l en-tete (Blizzard decale ses
-- boutons de quelques pixels les uns par rapport aux autres)
local function skinButton(b, anchor, wide)
    if buttons[b] then return buttons[b] end
    local C = ns.COLORS
    hideArt(b)
    local border, bg = tex(b, "BACKGROUND", -8), tex(b, "BACKGROUND", -7)
    bg:SetPoint("CENTER", anchor or b, "CENTER")
    bg:SetSize(BOX, BOX)
    border:SetPoint("TOPLEFT", bg, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    ns.UI.Gradient(bg, "VERTICAL", C.bg[1], C.bg[2], C.bg[3], 0.95, C.panel[1], C.panel[2], C.panel[3], 0.95)
    local hl = tex(b, "HIGHLIGHT")
    hl:SetAllPoints(bg)
    ns.UI.Gradient(hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.05, C.violet[1], C.violet[2], C.violet[3], 0.35)
    local s = { bg = bg, border = border, anchor = anchor or b, wide = wide }
    buttons[b] = s
    return s
end

-- position lisible (en combat, le jeu rend secretes celles de ses cadres :
-- aucun calcul dessus, on attend le releve suivant)
local issecret = issecretvalue or function() return false end
local function readable(v) return not issecret(v) and type(v) == "number" end

-- tous les carres sur la ligne du milieu de l en-tete
local function align(w, b)
    local s = buttons[b]
    local top = w:GetTop()
    local _, cy = s.anchor:GetCenter()
    if not readable(top) or not readable(cy) then return end
    local dy = math.floor((top - HEADER / 2) - cy + 0.5)
    local bw = s.wide and b:GetWidth()
    if s.wide and not readable(bw) then return end
    local width = s.wide and math.max(BOX, math.floor(bw + 0.5)) or BOX
    if s.dy == dy and s.width == width then return end
    s.dy, s.width = dy, width
    s.bg:ClearAllPoints()
    s.bg:SetPoint("CENTER", s.anchor, "CENTER", 0, dy)
    s.bg:SetSize(width, BOX)
end

-- trait d or (icones dessinees : chevron, moins, plus)
local function bar(b, s, w, h, x, y, rot)
    local t = tex(b, "OVERLAY", 7)
    t:SetSize(w, h)
    t:SetPoint("CENTER", s.bg, "CENTER", x, y)
    local C = ns.COLORS
    t:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    if rot then pcall(t.SetRotation, t, rot) end
    return t
end

local function skinButtons(w)
    -- type de compteur : chevron a la place de la fleche
    local dd = key(w, "DamageMeterTypeDropdown")
    local arrow = dd and key(dd, "Arrow")
    if dd and not buttons[dd] then
        local s = skinButton(dd, arrow)
        local chev = ns.UI.Chevron(dd, 12, "DOWN")
        ours[chev] = true
        chev:SetPoint("CENTER", s.bg, "CENTER", 0, 0)
    end
    -- session ("A", "G"...) : le texte reste, le cadre devient CorpUI
    local sess = key(w, "SessionDropdown")
    if sess and not buttons[sess] then
        local s = skinButton(sess, nil, true)
        -- notre texte, centre dans le carre (celui du jeu est decale)
        s.label = sess:CreateFontString(nil, "OVERLAY")
        ns.UI.HeadFont(s.label, 11)
        s.label:SetPoint("CENTER", s.bg, "CENTER", 0, 0)
        local C = ns.COLORS
        s.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    end
    -- recopie du nom de session du jeu ("A", "G"...), masque ensuite
    local name = sess and buttons[sess] and key(sess, "SessionName")
    if name and name.GetText then
        local ok, text = pcall(name.GetText, name)
        if ok then pcall(buttons[sess].label.SetText, buttons[sess].label, text or "") end
        pcall(name.SetAlpha, name, 0)
    end
    -- reglages : la roue de CorpUI
    local set = key(w, "SettingsDropdown")
    if set and not buttons[set] then
        local s = skinButton(set)
        local icon = tex(set, "OVERLAY", 7)
        icon:SetSize(14, 14)
        icon:SetPoint("CENTER", s.bg, "CENTER")
        -- roue grise du jeu : prend bien la teinte or (celle du micro-menu est trop sombre)
        icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
        -- en or, comme les autres icones de l en-tete
        icon:SetDesaturated(true)
        local C = ns.COLORS
        icon:SetVertexColor(math.min(1, C.gold[1] * 1.25), math.min(1, C.gold[2] * 1.25), math.min(1, C.gold[3] * 1.25))
    end
    -- reduire / deplier : moins, ou plus quand la fenetre est reduite
    local min = key(w, "MinimizeButton")
    if min and not buttons[min] then
        local s = skinButton(min)
        bar(min, s, 8, 2, 0, 0)
        s.vertical = bar(min, s, 2, 8, 0, 0)
    end
    if min and buttons[min] then buttons[min].vertical:SetShown(key(w, "isMinimized") and true or false) end
    -- les atlas changent avec l etat (survol, menu ouvert) : on re-masque
    for _, b in ipairs({ dd, sess, set, min }) do
        if b and buttons[b] then
            hideArt(b)
            align(w, b)
        end
    end
end

local function skinWindow(w)
    local C = ns.COLORS
    clear(key(w, "Header"))
    local mc = key(w, "MinimizeContainer")
    if mc then clear(key(mc, "Background")) end

    local p = CreateFrame("Frame", nil, w, "BackdropTemplate")
    p:SetAllPoints()
    p:SetFrameLevel(math.max(0, w:GetFrameLevel() - 1))
    ns.UI.SetBackdrop(p, 0.85)
    ns.UI.Shadow(p, 4)
    local strip = p:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT", 1, -1)
    strip:SetPoint("TOPRIGHT", -1, -1)
    strip:SetHeight(HEADER - 1)
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -HEADER)
    line:SetPoint("TOPRIGHT", p, "TOPRIGHT", -1, -HEADER)
    line:SetHeight(1)
    -- bandeau sombre et uni, sans filet
    strip:SetColorTexture(0, 0, 0, 0.4)
    line:Hide()
    windows[w] = p
end

-- lignes visibles d une fenetre : liste deroulante et ligne du joueur
local function scanEntries(w)
    local mc = key(w, "MinimizeContainer")
    if not mc then return end
    local box = key(mc, "ScrollBox")
    local target = box and key(box, "ScrollTarget")
    if target and target.GetChildren then
        for _, e in ipairs({ target:GetChildren() }) do pcall(skinEntry, e) end
    end
    local me = key(mc, "LocalPlayerEntry")
    if me then pcall(skinEntry, me) end
    -- detail d une source (sorts)
    local src = key(mc, "SourceWindow")
    if src and src.IsShown and src:IsShown() then
        local sbox = key(src, "ScrollBox")
        local st = sbox and key(sbox, "ScrollTarget")
        if st and st.GetChildren then
            for _, e in ipairs({ st:GetChildren() }) do pcall(skinEntry, e) end
        end
    end
end

local function scan()
    if not db or not db.enabled then return end
    for i = 1, 6 do
        local w = _G["DamageMeterSessionWindow" .. i]
        if type(w) == "table" and w.GetObjectType then
            if not windows[w] then pcall(skinWindow, w) end
            if w:IsShown() then
                scanEntries(w)
                local ok, err = pcall(skinButtons, w)
                if not ok and not btnErr then btnErr = true geterrorhandler()(err) end
            end
        end
    end
end

local ev = CreateFrame("Frame")
local since = 0
ev:SetScript("OnUpdate", function(_, dt)
    since = since + dt
    if since < 0.5 then return end
    since = 0
    scan()
end)
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if ns.ModuleOff("compteur", ev) then return end
    local root = ns.InitRoot()
    root.damage = root.damage or {}
    db = root.damage
    if db.enabled == nil then db.enabled = true end
end)

---------------------------------------------------------------------------
-- Reglage : sa case est dans le panneau Compteur (Compteur.lua), qui lit
-- et ecrit CorpUIDB.damage.enabled par ces deux fonctions. Activer habille
-- tout de suite les fenetres ouvertes ; desactiver demande un rechargement
-- (on ne defait pas l habillage), ce que dit le message.
---------------------------------------------------------------------------

function ns.DamageStyleEnabled()
    return db and db.enabled
end

function ns.SetDamageStyle(v)
    if not db then return end
    db.enabled = v
    if v then
        scan()
    elseif next(windows) then
        ns.Say(L.DMG_RELOAD)
    end
end

-- pas de panneau a lui : /corp degats ouvre le panneau Compteur
ns.RegisterModule({
    command = "degats",
    alias = "dps",
    title = function() return L.MOD_DMG end,
    desc = function() return L.DMG_DESC end,
    Slash = function() if ns.OpenMeterOptions then ns.OpenMeterOptions() end end,
})
