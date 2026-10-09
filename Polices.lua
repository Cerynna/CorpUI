--[[--------------------------------------------------------------------------
    CorpUI - polices
    Une police au choix (onglet General), Roboto par defaut, appliquee
    partout : toutes les polices de l interface (Blizzard et CorpUI, chat
    compris) changent de fichier en gardant leur taille et leur contour.
    Seule la methode SetFont des objets police est appelee : aucune variable
    globale de Blizzard n est ecrite (STANDARD_TEXT_FONT...).

    Polices : celles du registre (Media\Fonts\Fonts.lua) et celles ajoutees
    en jeu (nom du dossier : CorpUI essaie les fichiers habituels).
    Langues sans alphabet latin ni cyrillique (chinois, coreen) : la police
    du jeu reste, sauf police marquee cjk.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local BASE = ns.MEDIA .. "Fonts\\"
local CJK = { zhCN = true, zhTW = true, koKR = true }

local original = {}     -- objet police -> fichier d origine (pour revenir)
local probe

---------------------------------------------------------------------------
-- Liste des polices
---------------------------------------------------------------------------

function ns.FontList()
    local list = { { key = "Blizzard" } }
    for _, f in ipairs(ns.FONT_REGISTRY or {}) do table.insert(list, f) end
    local root = ns.root or {}
    for _, f in ipairs(root.fontsUser or {}) do table.insert(list, f) end
    return list
end

local function current()
    local key = ns.root and ns.root.font
    if key == nil then key = "Roboto" end           -- defaut demande
    for _, f in ipairs(ns.FontList()) do
        if f.key == key then return f end
    end
    return { key = "Blizzard" }
end

-- La police choisie s applique-t-elle a la langue du jeu ?
local function usable(f)
    if not f.regular then return false end
    if CJK[GetLocale()] and not f.cjk then return false end
    -- police sans cyrillique (Saira) : le client russe garde la sienne
    if f.latin and GetLocale() == "ruRU" then return false end
    return true
end

-- Fichier de la police choisie : "regular", "bold" ou "black"
-- (nil : garder la police du jeu)
function ns.FontFile(weight)
    local f = current()
    if not usable(f) then return nil end
    local rel = (weight == "black" and (f.black or f.bold)) or (weight == "bold" and f.bold) or f.regular
    return BASE .. (rel or f.regular)
end

function ns.FontKey() return current().key end

---------------------------------------------------------------------------
-- Application
---------------------------------------------------------------------------

local function fontObjects()
    local names = {}
    if GetFonts then
        local ok, list = pcall(GetFonts)
        if ok and type(list) == "table" then names = list end
    end
    return names
end

local function swap(obj, file)
    if type(obj) ~= "table" or not obj.GetFont or not obj.SetFont then return end
    local ok, cur, size, flags = pcall(obj.GetFont, obj)
    if not ok or not cur or not size then return end
    if not original[obj] then original[obj] = cur end
    pcall(obj.SetFont, obj, file or original[obj], size, flags or "")
end

function ns.ApplyFonts()
    local file = ns.FontFile("regular")
    if not file and not next(original) then return end      -- rien a faire ni a defaire
    for _, name in ipairs(fontObjects()) do
        swap(_G[name], file)
    end
    -- fenetres de chat et leurs zones de saisie (taille propre a chaque fenetre)
    for i = 1, 20 do
        swap(_G["ChatFrame" .. i], file)
        swap(_G["ChatFrame" .. i .. "EditBox"], file)
    end
end

---------------------------------------------------------------------------
-- Ajout d une police par son dossier
---------------------------------------------------------------------------

-- un fichier existe-t-il ? on l essaie sur un texte cache
local function exists(rel)
    if not probe then
        local f = CreateFrame("Frame")
        f:Hide()
        probe = f:CreateFontString(nil, "OVERLAY")
    end
    probe:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    local full = BASE .. rel
    local ok, res = pcall(probe.SetFont, probe, full, 12, "")
    if not ok or res == false then return false end
    -- fichier absent : le texte garde la police precedente
    local got = probe:GetFont()
    return type(got) == "string" and got:lower() == full:lower()
end

local function find(dir, weights)
    for _, w in ipairs(weights) do
        for _, pattern in ipairs({ "%s\\static\\%s-%s", "%s\\%s-%s", "%s\\%s" }) do
            for _, ext in ipairs({ ".ttf", ".otf", ".TTF" }) do
                local rel
                if pattern == "%s\\%s" then
                    rel = string.format(pattern, dir, w) .. ext
                else
                    rel = string.format(pattern, dir, dir, w) .. ext
                end
                if exists(rel) then return rel end
            end
        end
    end
    -- un seul fichier au nom du dossier
    for _, ext in ipairs({ ".ttf", ".otf", ".TTF" }) do
        if exists(dir .. "\\" .. dir .. ext) then return dir .. "\\" .. dir .. ext end
    end
end

function ns.AddFont(dir)
    dir = (dir or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if dir == "" then return false end
    for _, f in ipairs(ns.FontList()) do
        if f.key:lower() == dir:lower() then return true, f.key end
    end
    local regular = find(dir, { "Medium", "Regular", "Book", "Normal" })
    if not regular then return false end
    local entry = {
        key = dir,
        regular = regular,
        bold = find(dir, { "Bold", "SemiBold", "Semibold" }) or regular,
        black = find(dir, { "Black", "ExtraBold", "Heavy", "Bold" }) or regular,
    }
    ns.root.fontsUser = ns.root.fontsUser or {}
    table.insert(ns.root.fontsUser, entry)
    return true, dir
end

---------------------------------------------------------------------------
-- Reglage dans l onglet General
---------------------------------------------------------------------------

-- form (facultatif) : formulaire ns.UI.Form du panneau ; sinon, le reglage
-- se place sous anchor (assistant d installation)
function ns.BuildFontOptions(panel, anchor, form)
    -- choix : liste deroulante des polices connues
    local function options()
        local list = {}
        for _, f in ipairs(ns.FontList()) do
            table.insert(list, { value = f.key, text = f.key == "Blizzard" and L.GEN_FONT_BLIZZ or f.key })
        end
        return list
    end
    local function get() return current().key end
    local function set(key)
        ns.root.font = key
        ns.ApplyFonts()
        if ns.ApplyEngineFonts then ns.ApplyEngineFonts() end
    end
    local sel, show
    if form then
        form:Header(L.GEN_FONT)
        sel = form:Select(nil, options, get, set, 160)
        show = form.Changed
    else
        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
        title:SetText(L.GEN_FONT)
        sel = ns.UI.Select(panel, 160, options, get, set, function() sel:Refresh() end)
        sel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        show = function() sel:Refresh() end
    end

    -- ajout : nom du dossier cree dans Media\Fonts
    local edit = ns.UI.EditBox(panel, 110, 20)
    edit:SetSize(110, 20)
    edit:SetPoint("LEFT", sel, "RIGHT", 18, 0)
    edit:SetAutoFocus(false)
    local add = ns.UI.Button(panel, L.GEN_FONT_ADD, 70, function()
        local ok, key = ns.AddFont(edit:GetText())
        if ok then
            ns.root.font = key
            ns.ApplyFonts()
            show()
            ns.Say(string.format(L.GEN_FONT_ADDED, key))
            edit:SetText("")
        else
            ns.Say(string.format(L.GEN_FONT_NOTFOUND, edit:GetText()))
        end
        edit:ClearFocus()
    end)
    add:SetPoint("LEFT", edit, "RIGHT", 6, 0)
    edit:SetScript("OnEnterPressed", function() add:Click() end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    if form then
        hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y + 2)
    else
        hint:SetPoint("TOPLEFT", sel, "BOTTOMLEFT", 0, -6)
    end
    hint:SetWidth(400)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.GEN_FONT_HINT)
    if not form then show() end
    return hint
end

---------------------------------------------------------------------------

-- Noms au-dessus des tetes et chiffres de degats flottants : dessines par
-- le moteur, avec la police lue dans UNIT_NAME_FONT / DAMAGE_TEXT_FONT au
-- chargement du monde. Aucun script de Blizzard ne lit ces deux variables
-- (verifie dans le code de ce client, branche forever) : seul le moteur
-- s en sert, on peut donc les regler sans marquer de code Blizzard. Prend
-- effet au chargement suivant (rechargement ou connexion).
local engineDefault
local function applyEngineFonts()
    -- valeurs du jeu gardees pour pouvoir revenir a sa police
    engineDefault = engineDefault or { UNIT_NAME_FONT, DAMAGE_TEXT_FONT }
    local names = ns.FontFile("bold")
    if names then
        UNIT_NAME_FONT = names
        DAMAGE_TEXT_FONT = ns.FontFile("black") or names
    elseif engineDefault[1] then
        UNIT_NAME_FONT, DAMAGE_TEXT_FONT = engineDefault[1], engineDefault[2]
    end
end
ns.ApplyEngineFonts = applyEngineFonts

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" then
        -- sauvegarde disponible : la police choisie est connue
        if addon == "CorpUI" then
            ns.InitRoot()
            applyEngineFonts()
        end
        return
    end
    ns.InitRoot()
    ns.ApplyFonts()
    -- certaines fenetres (chat, chargees a la demande) arrivent plus tard
    C_Timer.After(2, ns.ApplyFonts)
end)
