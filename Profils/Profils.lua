--[[--------------------------------------------------------------------------
    CorpUI - module Profils
    Les reglages de CorpUI (theme, police, cadres, barres, positions...)
    forment un profil. Chaque personnage utilise un profil ("Default" au
    depart) ; plusieurs personnages peuvent partager le meme.

    Les reglages "vivants" sont ceux de CorpUIDB (les modules les lisent a la
    connexion) : ce sont ceux du profil actif. Au changement de personnage
    ou de profil, ils sont ranges dans root.profiles[actif] puis remplaces
    par ceux du profil voulu, avant que les modules ne les lisent (au
    chargement de l addon). Changer de profil en jeu demande donc un
    rechargement.

    Hors profil : les donnees propres aux personnages (suivi d experience,
    quantites de reactifs, attributions de buffs, sorts au clic, liste des
    personnages), la langue, les polices ajoutees, la fenetre CorpUI.

    Export / import : texte "CorpUI:1:" + table ecrite par nous et relue par
    notre propre lecteur (jamais execute : pas de loadstring).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local DEFAULT = "Default"
local PREFIX = "CorpUI:1:"

-- sous-tables de CorpUIDB qui font partie d un profil ; pour chacune, les
-- cles de donnees qui restent au compte (jamais copiees ni ecrasees)
local KEYS = {
    theme = {}, font = {}, minimap = {}, movers = {},
    frames = { diag = true }, group = {}, bars = {}, cast = {}, auras = {}, menus = {},
    xp = { chars = true }, map = {}, info = {}, quests = {}, bags = {}, chat = {},
    tooltips = {}, damage = {}, plates = {}, skins = {}, shop = {},
    talents = { guide = true, stageBlocked = true },
    reminders = { choice = true }, reagents = { targets = true },
    crafting = { queues = true, recipes = true, known = true, pane = true, shopWin = true },
    buffs = { groups = true, assign = true, indiv = true, aura = true, tab = true, win = true },
    -- ajoutees le 06/10 (oubliees : un meme panneau suivait le profil a moitie)
    resources = {}, meter = {}, loot = {}, raid = { diag = true },
    dispel = { assign = true }, cd = { chars = true, diag = true },
    -- ajoutees le 09/10 (style Moderne) : centre de l ecran
    center = {},
    -- ajoutee le 10/10 : fenetre de menace
    threat = {},
    -- ajoutee le 10/10 : modules allumes / coupes (page Modules)
    modules = {},
}

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

-- reglages vivants -> profil
local function snapshot(db)
    local snap = {}
    for k, keep in pairs(KEYS) do
        local v = db[k]
        if type(v) == "table" then
            local t = {}
            for kk, x in pairs(v) do
                if not keep[kk] then t[kk] = copy(x) end
            end
            snap[k] = t
        elseif v ~= nil then
            snap[k] = v
        end
    end
    return snap
end

-- profil -> reglages vivants (les donnees des personnages restent)
local function load(db, snap)
    for k, keep in pairs(KEYS) do
        local old = db[k]
        local new = copy(snap[k])
        if type(old) == "table" and next(keep) then
            if type(new) ~= "table" then new = {} end
            for kk in pairs(keep) do new[kk] = old[kk] end
        end
        db[k] = new
    end
end

local function charKnown()
    local name = UnitName("player")
    return name and name ~= "" and name ~= UNKNOWNOBJECT
end

---------------------------------------------------------------------------
-- Changement de profil au chargement (appele par ns.InitRoot)
---------------------------------------------------------------------------

local switched = false

function ns.ProfileSwitch(db)
    if switched or not charKnown() then return end
    switched = true
    db.profiles = db.profiles or {}
    db.profileOf = db.profileOf or {}
    db.activeProfile = db.activeProfile or DEFAULT
    local key = ns.CharKey()
    -- personnage jamais vu par CorpUI (premiere installation comprise) :
    -- Discussion/Chat.lua lui pose les onglets par defaut
    ns.NEW_CHAR = db.profileOf[key] == nil
    local want = db.profileOf[key] or db.activeProfile
    if want ~= db.activeProfile and not db.profiles[want] then want = db.activeProfile end
    db.profileOf[key] = want
    if want ~= db.activeProfile then
        db.profiles[db.activeProfile] = snapshot(db)
        load(db, db.profiles[want])
        db.activeProfile = want
    end
    return true
end

local function root() return ns.InitRoot() end

local function saveLive()
    local db = root()
    db.profiles = db.profiles or {}
    db.profiles[db.activeProfile or DEFAULT] = snapshot(db)
end

local function names()
    local db = root()
    local list, seen = {}, {}
    local function add(n) if n and not seen[n] then seen[n] = true table.insert(list, n) end end
    add(DEFAULT)
    add(db.activeProfile)
    for n in pairs(db.profiles or {}) do add(n) end
    table.sort(list, function(a, b)
        if a == DEFAULT then return true elseif b == DEFAULT then return false end
        return a:lower() < b:lower()
    end)
    return list
end

local function label(n) return n == DEFAULT and L.PROF_DEFAULT or n end

-- pour l assistant d installation
ns.ProfileNames, ns.ProfileLabel = names, label
function ns.CharProfile()
    local db = root()
    return db.profileOf and db.profileOf[ns.CharKey()] or db.activeProfile or DEFAULT
end
-- le personnage prendra ce profil au prochain chargement
function ns.SetCharProfile(n)
    local db = root()
    db.profileOf = db.profileOf or {}
    db.profileOf[ns.CharKey()] = n
end

---------------------------------------------------------------------------
-- Ecriture / lecture du texte d export
---------------------------------------------------------------------------

local function write(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
            local tk, tx = type(k), type(x)
            if (tk == "string" or tk == "number") and (tx == "table" or tx == "string" or tx == "number" or tx == "boolean") then
                write(k, out)
                out[#out + 1] = "="
                write(x, out)
                out[#out + 1] = ";"
            end
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = '"' .. v:gsub('[\\"]', "\\%0"):gsub("\n", "\\n") .. '"'
    elseif t == "number" then
        out[#out + 1] = string.format("%.10g", v)
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    end
end

local function read(s)
    local i, n = 1, #s
    local value
    local function skip() i = s:find("%S", i) or n + 1 end
    function value(depth)
        if depth > 40 then error("depth") end
        skip()
        local c = s:sub(i, i)
        if c == "{" then
            i = i + 1
            local t = {}
            while true do
                skip()
                if s:sub(i, i) == "}" then i = i + 1 return t end
                local k = value(depth + 1)
                skip()
                if s:sub(i, i) ~= "=" or k == nil or type(k) == "table" then error("key") end
                i = i + 1
                t[k] = value(depth + 1)
                skip()
                if s:sub(i, i) == ";" then i = i + 1 end
            end
        elseif c == '"' then
            local buf = {}
            i = i + 1
            while true do
                local ch = s:sub(i, i)
                if ch == "" then error("string") end
                if ch == "\\" then
                    local nx = s:sub(i + 1, i + 1)
                    buf[#buf + 1] = (nx == "n") and "\n" or nx
                    i = i + 2
                elseif ch == '"' then
                    i = i + 1
                    return table.concat(buf)
                else
                    local j = s:find('[\\"]', i) or n + 1
                    buf[#buf + 1] = s:sub(i, j - 1)
                    i = j
                end
            end
        elseif c == "T" then i = i + 1 return true
        elseif c == "F" then i = i + 1 return false
        else
            local num = s:match("^-?[%d%.]+[eE]?[-+]?%d*", i)
            local v = num and tonumber(num)
            if not v then error("value") end
            i = i + #num
            return v
        end
    end
    local ok, v = pcall(value, 0)
    if ok and type(v) == "table" then return v end
end

local function export()
    local out = {}
    write({ name = root().activeProfile or DEFAULT, data = snapshot(root()) }, out)
    return PREFIX .. table.concat(out)
end

local function import(text)
    text = (text or ""):gsub("^%s+", "")
    if text:sub(1, #PREFIX) ~= PREFIX then return end
    local t = read(text:sub(#PREFIX + 1))
    if not t or type(t.data) ~= "table" then return end
    -- seules les sous-tables connues sont gardees
    local data = {}
    for k in pairs(KEYS) do data[k] = t.data[k] end
    return data, type(t.name) == "string" and t.name or nil
end

ns.ProfileCodec = { export = export, import = import }

---------------------------------------------------------------------------
-- Panneau
---------------------------------------------------------------------------

local win

-- bouton a confirmer : premier clic -> "Sur ?", second clic dans les 3 s
-- reload : bouton de rechargement (fn renvoie false pour ne pas recharger)
local function confirmButton(parent, text, fn, reload)
    local b
    local function click()
        if b.armed then
            b.armed = false
            b:SetText(text)
            return fn()
        end
        b.armed = true
        b:SetText(L.PROF_CONFIRM)
        C_Timer.After(3, function() if b.armed then b.armed = false b:SetText(text) end end)
        return false
    end
    if reload then
        b = ns.UI.ReloadButton(parent, text, 90, click)
    else
        b = ns.UI.Button(parent, text, 90, function() click() end)
    end
    return b
end

local function buildWindow()
    win = ns.UI.Window("CorpUIProfilesOptions", ns.TITLE .. " - " .. L.MOD_PROFILES, nil, 460, 350)
    local C = ns.COLORS
    local function hex(v) return math.floor(v * 255 + 0.5) end
    local gold = "|cff" .. string.format("%02x%02x%02x", hex(C.gold[1]), hex(C.gold[2]), hex(C.gold[3]))
    local selected
    local refresh
    local form = ns.UI.Form(win, -34, function() refresh() end)

    local cur = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cur:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 2)
    form:Gap(22)

    -- choix du profil : liste deroulante, le profil actif en or
    -- boutons securises (rechargement) : leur chaine d ancrage ne doit passer
    -- par aucun texte ("Cannot anchor protected frames to regions") ; la
    -- liste est un bouton ancre sur le panneau
    local picker = form:Select(nil, function()
        local db, list = root(), {}
        for _, n in ipairs(names()) do
            table.insert(list, { value = n, text = n == db.activeProfile and (gold .. label(n) .. "|r") or label(n) })
        end
        return list
    end, function() return selected end, function(v) selected = v end, 140)
    local used = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    used:SetPoint("TOPLEFT", win, "TOPLEFT", 12, form.y + 2)
    used:SetWidth(420)
    used:SetJustifyH("LEFT")
    used:SetWordWrap(false)
    form:Gap(18)

    local use = ns.UI.ReloadButton(win, L.PROF_USE, 70, function()
        local db = root()
        if selected == db.activeProfile then return false end
        db.profileOf[ns.CharKey()] = selected
    end)
    use:SetPoint("LEFT", picker, "RIGHT", 8, 0)
    local copyBtn = confirmButton(win, L.PROF_COPY, function()
        local db = root()
        if selected == db.activeProfile then return false end
        saveLive()
        load(db, db.profiles[selected] or {})
        saveLive()
    end, true)
    copyBtn:SetPoint("LEFT", use, "RIGHT", 4, 0)
    local del = confirmButton(win, L.PROF_DELETE, function()
        local db = root()
        if selected == db.activeProfile or selected == DEFAULT then
            ns.Say(L.PROF_DEL_ACTIVE)
            return
        end
        db.profiles[selected] = nil
        for k, n in pairs(db.profileOf) do if n == selected then db.profileOf[k] = nil end end
        ns.Say(string.format(L.PROF_DELETED, selected))
        selected = db.activeProfile
        refresh()
    end)
    del:SetPoint("LEFT", copyBtn, "RIGHT", 4, 0)

    -- nouveau profil : copie des reglages actuels
    local edit = ns.UI.EditBox(win, 150, 20)
    edit:SetSize(150, 20)
    form:Gap(4)
    edit:SetPoint("TOPLEFT", win, "TOPLEFT", 12, form.y - 1)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(32)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local new = ns.UI.Button(win, L.PROF_NEW, 70, function()
        local n = strtrim(edit:GetText() or "")
        local db = root()
        if n == "" then ns.Say(L.PROF_NONAME) return end
        if n == DEFAULT or db.profiles[n] or n == db.activeProfile then ns.Say(string.format(L.PROF_EXISTS, n)) return end
        saveLive()
        db.profiles[n] = snapshot(db)
        db.activeProfile = n
        db.profileOf[ns.CharKey()] = n
        edit:SetText("")
        edit:ClearFocus()
        ns.Say(string.format(L.PROF_CREATED, n))
        selected = n
        refresh()
    end)
    new:SetPoint("LEFT", edit, "RIGHT", 8, 0)
    local reset = confirmButton(win, L.PROF_RESET, function()
        local db = root()
        -- reglages par defaut (Defauts.lua : style Moderne et disposition de
        -- reference), les donnees des personnages restent ; le reste revient
        -- aux valeurs des modules (interface Blizzard masquee, etc.)
        load(db, ns.DefaultProfile and ns.DefaultProfile() or {})
        saveLive()
    end, true)
    reset:SetPoint("LEFT", new, "RIGHT", 4, 0)
    form:Gap(28)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y)
    hint:SetWidth(430)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.PROF_HINT)
    form:Gap(34)

    -- partage
    form:Header(L.PROF_SHARE)
    local box = CreateFrame("Frame", nil, win)
    box:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y)
    box:SetSize(430, 70)
    form:Gap(76)
    ns.UI.Skin(box, 0.6)
    local sf = CreateFrame("ScrollFrame", nil, box)
    sf:SetPoint("TOPLEFT", 6, -5)
    sf:SetPoint("BOTTOMRIGHT", -6, 5)
    local text = CreateFrame("EditBox", nil, sf)
    text:SetMultiLine(true)
    text:SetAutoFocus(false)
    text:SetFontObject("GameFontHighlightSmall")
    text:SetWidth(410)
    text:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(text)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, text:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 20)))
    end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() text:SetFocus() end)

    local exp = ns.UI.Button(win, L.PROF_EXPORT, 90, function()
        saveLive()
        text:SetText(export())
        text:SetFocus()
        text:HighlightText()
    end)
    exp:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y)
    form:Gap(30)
    local imp = ns.UI.ReloadButton(win, L.PROF_IMPORT, 90, function()
        local data, from = import(text:GetText())
        if not data then ns.Say(L.PROF_BAD) return false end
        local db = root()
        local n = strtrim(edit:GetText() or "")
        if n == "" then n = from or "Import" end
        if n == DEFAULT or n == db.activeProfile then n = n .. " 2" end
        local base, i = n, 2
        while db.profiles[n] do n = base .. " " .. i i = i + 1 end
        saveLive()
        db.profiles[n] = data
        db.profileOf[ns.CharKey()] = n
    end)
    imp:SetPoint("LEFT", exp, "RIGHT", 4, 0)
    local shareHint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    shareHint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y)
    shareHint:SetWidth(430)
    shareHint:SetJustifyH("LEFT")
    shareHint:SetText(L.PROF_SHARE_HINT)
    win:SetHeight(math.floor(50 - form.y))

    refresh = function()
        local db = root()
        cur:SetText(string.format(L.PROF_CURRENT, gold .. label(db.activeProfile or DEFAULT) .. "|r"))
        selected = selected or db.activeProfile or DEFAULT
        picker:Refresh()
        local who = {}
        for k, n in pairs(db.profileOf or {}) do
            if n == selected then table.insert(who, (k:match("^([^-]+)") or k)) end
        end
        table.sort(who)
        used:SetText(#who > 0 and string.format(L.PROF_USED_BY, table.concat(who, ", ")) or "")
        local other = selected ~= db.activeProfile
        use:SetEnabled(other)
        copyBtn:SetEnabled(other)
        del:SetEnabled(other and selected ~= DEFAULT)
    end
    win:HookScript("OnShow", function()
        selected = nil
        refresh()
    end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- nom du personnage inconnu au chargement : rattrapage (rare)
        local db = root()
        if ns.ProfileSwitch(db) then
            ns.RootDefaults(db)
            ns.ApplyTheme(db.theme)
        end
    elseif event == "PLAYER_LOGOUT" then
        -- les reglages vivants sont ceux du profil actif : on les y range
        if ns.root and ns.root.activeProfile then saveLive() end
    end
end)

ns.RegisterModule({
    command = "profils",
    alias = "profiles",
    panelName = "CorpUIProfilesOptions",
    icon = "Interface\\Icons\\INV_Misc_Book_11",
    title = function() return L.MOD_PROFILES end,
    desc = function() return L.PROF_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})
