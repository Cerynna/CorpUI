--[[--------------------------------------------------------------------------
    CorpUI - module Erreurs (facon BugGrabber + BugSack)
      - capture : le gestionnaire d erreurs du jeu (seterrorhandler) est
        remplace des le chargement de ce fichier (tot dans le .toc). Celui
        de Blizzard (HandleLuaError) n accepte d abonnes qu en code
        securise ; sa fenetre d erreur ne s ouvre donc plus. Chaque erreur
        reste ecrite dans Logs\General.log (C_Log.LogErrorMessage, comme
        Blizzard) ;
      - une erreur : message, pile d appels, variables locales (debugstack
        et debuglocals au niveau de l erreur, meme calcul que Blizzard) ;
        deja vue (meme message, meme ligne fautive dans la pile) : elle
        compte une fois de plus et repasse en tete ; valeur secrete :
        "(illisible)" ;
      - aussi notes : actions bloquees ou interdites a un addon
        (ADDON_ACTION_BLOCKED / FORBIDDEN), avec la pile d appels et les
        locales du code fautif (l evenement part pendant l appel bloque),
        et avertissements Lua ;
      - chaque erreur garde son contexte (version de CorpUI, personnage,
        zone, combat, groupe) ;
      - icone dans la barre d icones de la minicarte (a cote du suivi et du
        courrier), avec le nombre d erreurs de la session ; clic : la
        fenetre (une erreur par page, cette session ou toutes) ; le texte
        est un rapport a coller tel quel sur Discord (mise en forme
        Markdown, 2000 caracteres au plus, ou complet), « Copier » le
        selectionne pour Ctrl+C ; sans minicarte CorpUI : icone libre au
        coin de la carte ;
      - gardees d une session a l autre (200 au plus), au niveau du compte.
    Module coupe (page Modules) : le gestionnaire du jeu est remis a la
    connexion et les erreurs du chargement lui sont rendues.
----------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end
local function readable(v)
    if v == nil then return false end
    if canaccessvalue then
        local ok, r = pcall(canaccessvalue, v)
        return ok and r and true or false
    end
    return not issecret(v)
end

local MAX_ERRORS = 200
local MAX_TEXT = 4000

local db                      -- CorpUIDB.errors = { list, session, opt }
local sessionId
local pending = {}            -- erreurs arrivees avant la sauvegarde
local handling = false
local installed = false
local blizzHandler = geterrorhandler and geterrorhandler() or nil
local notify                  -- icone et fenetre a jour (pose plus bas)

local function clip(s)
    if #s > MAX_TEXT then s = s:sub(1, MAX_TEXT) .. "\n..." end
    return s
end

-- texte sur : chaine lisible, coupee ; sinon "(illisible)"
local function safeText(v)
    if v == nil then return nil end
    if not readable(v) then return L.ERR_SECRET end
    if type(v) ~= "string" then v = tostring(v) end
    return clip(v)
end

---------------------------------------------------------------------------
-- Rangement
---------------------------------------------------------------------------

local function firstLine(s)
    return type(s) == "string" and (s:match("^[^\n]*") or "") or ""
end

-- ligne de pile qui distingue une erreur : celle du code fautif, pas
-- d une fonction C (SetPoint, error) ni d un appel terminal
local function keyLine(s)
    if type(s) ~= "string" then return "" end
    for line in s:gmatch("[^\n]+") do
        if not line:find("[C]", 1, true) and not line:find("tail call", 1, true) then return line end
    end
    return firstLine(s)
end

local function store(e)
    if not db then
        if #pending < MAX_ERRORS then pending[#pending + 1] = e end
        return
    end
    local key = (e.raw or e.msg or "") .. "\n" .. keyLine(e.stack)
    local list = db.list
    for i = #list, 1, -1 do
        local x = list[i]
        if x.key == key then
            x.count = (x.count or 1) + 1
            x.last = e.time
            -- contexte de la derniere fois
            x.ctx, x.raw, x.kind = e.ctx or x.ctx, e.raw or x.raw, e.kind or x.kind
            if x.session == sessionId then
                x.sessCount = (x.sessCount or 1) + 1
            else
                x.session, x.sessCount = sessionId, 1
                -- nouvelle dans cette session : pile et locales du jour
                x.stack, x.locals = e.stack or x.stack, e.locals or x.locals
            end
            -- la plus recente en dernier
            table.remove(list, i)
            list[#list + 1] = x
            if notify then notify(x, false) end
            return x
        end
    end
    e.key = key
    e.count, e.sessCount = 1, 1
    e.first, e.last = e.time, e.time
    e.session = sessionId
    list[#list + 1] = e
    while #list > MAX_ERRORS do table.remove(list, 1) end
    if notify then notify(e, true) end
    return e
end

---------------------------------------------------------------------------
-- Capture
---------------------------------------------------------------------------

-- pile et locales au niveau de l erreur : meme calcul que Blizzard
-- (Blizzard_ScriptErrors, GetErrorData), appele directement par le
-- gestionnaire (la hauteur de pile en depend)
local function errorData()
    local level = 3
    if GetCallstackHeight and GetErrorCallstackHeight then
        local cur = GetCallstackHeight()
        local errH = GetErrorCallstackHeight()
        if type(cur) == "number" then level = cur - ((type(errH) == "number") and (errH - 1) or 0) end
    end
    local stack = debugstack and debugstack(level) or nil
    local locals = debuglocals and debuglocals(level, true) or nil
    return stack, locals
end

-- pile et locales d une action bloquee : l evenement part pendant l appel
-- fautif ; on saute nos propres niveaux (ce fichier, et le pcall entre
-- eux), la pile commence a la fonction protegee ([C]) et les locales sont
-- celles du premier code Lua
local SELF = "CorpUI/Erreurs/Erreurs.lua"
local function blockedData()
    if not debugstack then return nil, nil end
    local first, lua
    for level = 2, 24 do
        local line = debugstack(level, 1, 0)
        if type(line) ~= "string" or line == "" or not readable(line) then break end
        if (line:gsub("\\", "/")):find(SELF, 1, true) then
            first = nil
        else
            first = first or level
            if not line:find("[C]", 1, true) and not line:find("tail call", 1, true) then
                lua = level
                break
            end
        end
    end
    if not first then return nil, nil end
    local stack = debugstack(first)
    local locals = lua and debuglocals and debuglocals(lua, true) or nil
    return stack, locals
end

-- contexte au moment de l erreur
local function context()
    local c = { ver = ns.VERSION }
    pcall(function()
        c.combat = InCombatLockdown() and true or false
        local z = GetRealZoneText()
        if readable(z) and z ~= "" then c.zone = z end
        local cls = UnitClass("player")
        if readable(cls) then c.class = cls end
        local lvl = UnitLevel("player")
        if readable(lvl) and lvl > 0 then c.level = lvl end
        if IsInRaid() then c.group = "raid" elseif IsInGroup() then c.group = "party" end
        local n = c.group and GetNumGroupMembers()
        if n and readable(n) then c.size = n end
    end)
    return c
end

local function cleanLocals(lo)
    lo = safeText(lo)
    if lo and lo ~= L.ERR_SECRET then lo = lo:gsub("|([kK])", "%1") end
    return lo
end

local function record(msg, stack, locals)
    local m = safeText(msg) or "?"
    -- journal du jeu (Logs\General.log), comme le gestionnaire de Blizzard
    if C_Log and C_Log.LogErrorMessage and readable(msg) and (stack == nil or readable(stack)) then
        pcall(C_Log.LogErrorMessage, string.format("Lua Error: %s\n%s", tostring(msg), tostring(stack or "")))
    end
    return store({ msg = m, stack = safeText(stack), locals = cleanLocals(locals), time = time(),
                   kind = "error", ctx = context() })
end

-- avalanche (la meme erreur a chaque image) : dans la seconde qui suit,
-- elle est seulement comptee, sans relire pile et locales (couteux)
local stormMsg, stormAt, stormEntry = nil, 0, nil
local function storming(plain, now)
    if not (plain and plain == stormMsg and stormEntry and now - stormAt < 1 and now >= stormAt) then return false end
    stormEntry.count = (stormEntry.count or 1) + 1
    stormEntry.sessCount = (stormEntry.sessCount or 1) + 1
    stormEntry.last = time()
    stormAt = now
    if notify then pcall(notify, stormEntry, false) end
    return true
end

local function onError(msg)
    if handling then return end
    handling = true
    local now = GetTime()
    local plain = type(msg) == "string" and not issecret(msg) and msg or nil
    if storming(plain, now) then handling = false return end
    local stack, locals = errorData()
    local ok, e = pcall(record, msg, stack, locals)
    stormMsg, stormAt, stormEntry = plain, now, ok and e or nil
    handling = false
end
ns._errOnError = onError

if seterrorhandler then
    pcall(seterrorhandler, onError)
    installed = geterrorhandler and geterrorhandler() == onError or false
end

-- actions bloquees ou interdites, avertissements Lua ; raw : le texte
-- d origine (celui de BugSack et du journal des souillures)
local function onAction(event, a, b)
    local now = GetTime()
    local e, msg
    if event == "LUA_WARNING" then
        local text = safeText(b) or safeText(a) or "?"
        msg = string.format(L.ERR_WARNING, text)
        if storming(msg, now) then return end
        e = store({ msg = msg, raw = "[LUA_WARNING] " .. text, time = time(), kind = "warning", ctx = context() })
    else
        local who, what = safeText(a) or "?", safeText(b) or "?"
        local kind = event == "ADDON_ACTION_BLOCKED" and "blocked" or "forbidden"
        msg = string.format(kind == "blocked" and L.ERR_BLOCKED or L.ERR_FORBIDDEN, who, what)
        if storming(msg, now) then return end
        local stack, locals = blockedData()
        e = store({ msg = msg, time = time(), kind = kind, ctx = context(),
                    raw = string.format("[%s] AddOn '%s' tried to call the protected function '%s'.", event, who, what),
                    stack = safeText(stack), locals = cleanLocals(locals) })
    end
    stormMsg, stormAt, stormEntry = msg, now, e
end

local cap = CreateFrame("Frame")
cap:SetScript("OnEvent", function(_, event, a, b)
    if handling then return end
    handling = true
    pcall(onAction, event, a, b)
    handling = false
end)
for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "LUA_WARNING" }) do
    pcall(cap.RegisterEvent, cap, e)
end

---------------------------------------------------------------------------
-- Icone (barre d icones de la minicarte, Minicarte.lua)
---------------------------------------------------------------------------

local btn                       -- l icone
local win                       -- la fenetre
local pulseUntil = 0

local function sessionList()
    local out = {}
    if not db then return out end
    for _, e in ipairs(db.list) do
        if e.session == sessionId then out[#out + 1] = e end
    end
    return out
end

local function sessionTotals()
    local unique, times = 0, 0
    for _, e in ipairs(sessionList()) do
        unique = unique + 1
        times = times + (e.sessCount or 1)
    end
    return unique, times
end

local function paintButton()
    if not btn then return end
    local unique = sessionTotals()
    btn.count:SetText(unique > 0 and (unique > 99 and "99+" or tostring(unique)) or "")
    btn.icon:SetDesaturated(unique == 0)
    btn.icon:SetAlpha(unique > 0 and 1 or 0.5)
    btn.want = (unique > 0 or (db and db.opt.always)) and true or false
    if btn.free then
        btn:SetShown(btn.want)
    elseif ns.MapIconsRefresh then
        ns.MapIconsRefresh()
    end
end

local function buttonTip(self)
    local t = ns.Tooltip(self, "ANCHOR_BOTTOMLEFT")
    t:AddLine(L.ERR_TITLE)
    local unique, times = sessionTotals()
    if unique == 0 then
        t:AddLine(L.ERR_NONE, 0.6, 0.6, 0.6)
    else
        t:AddLine(string.format(L.ERR_TIP_COUNT, unique, times), 1, 1, 1)
        local last = sessionList()[unique]
        if last then t:AddLine(firstLine(last.msg), 1, 0.4, 0.4, true) end
    end
    if not installed then t:AddLine(L.ERR_NOT_INSTALLED, 1, 0.5, 0.3, true) end
    t:AddLine(L.ERR_TIP_CLICK, 0.6, 0.6, 0.6)
    t:Show()
end

local function setupButton(b)
    btn = b
    b.icon:SetTexture("Interface\\Icons\\Spell_Nature_InsectSwarm")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 3, -2)
    b.count:SetTextColor(1, 0.3, 0.3)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() if ns.ErrorsToggle then ns.ErrorsToggle() end end)
    b:SetScript("OnEnter", buttonTip)
    -- nouvelle erreur : le liseré clignote quelques secondes
    b:HookScript("OnUpdate", function(self)
        if not self.cuiBorder then return end
        local now = GetTime()
        if now < pulseUntil then
            local a = 0.5 + 0.5 * math.abs(math.sin(now * 6))
            self.cuiBorder:SetColorTexture(1, 0.25 * a, 0.25 * a, 1)
            self.pulsing = true
        elseif self.pulsing then
            self.pulsing = false
            ns.UI.ResetBorder(self)
        end
    end)
    paintButton()
end

-- Minicarte.lua cree le bouton dans sa barre (meme style que le courrier)
ns.MapIconsExtra = ns.MapIconsExtra or {}
table.insert(ns.MapIconsExtra, { key = "errors", setup = setupButton })

-- sans minicarte CorpUI : petit bouton libre au coin de la carte
local function freeButton()
    if btn or not Minimap then return end
    local b = CreateFrame("Button", "CorpUIErrorsButton", Minimap)
    b:SetSize(18, 18)
    b:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -2)
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    ns.UI.Skin(b, 0.85)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetScript("OnLeave", ns.HideTooltip)
    b.free = true
    setupButton(b)
end

---------------------------------------------------------------------------
-- Fenetre : une erreur par page
---------------------------------------------------------------------------

local view = { all = false, index = nil, full = false }
local sureUntil = 0

local function currentList()
    if view.all then return db and db.list or {} end
    return sessionList()
end

local function stamp(t)
    return t and date(L.ERR_DATE, t) or "?"
end

---------------------------------------------------------------------------
-- Rapport a coller sur Discord
--   **CorpUI 2.0.6** · Action bloquee
--   -# WoW 1.15.7 (61000) · frFR · Guerrier 60 · Orgrimmar · en combat · seul
--   -# 9 fois · premiere ... · derniere ... · 4 cette session
--   ```lua
--   [ADDON_ACTION_BLOCKED] AddOn 'CorpUI_Sacs' tried to call ...
--   -- Pile d'appels :
--   ...
--   -- Variables locales :
--   ...
--   ```
--   -# Autres addons : ... · CorpUI coupes : ...
-- Format Discord : 2000 caracteres au plus (limite d un message), les
-- locales puis la fin de la pile sautent ; format complet : tout.
---------------------------------------------------------------------------

local DISCORD_MAX = 1990
local FENCE = "```"
local KIND = { error = "ERR_K_ERROR", blocked = "ERR_K_BLOCKED", forbidden = "ERR_K_FORBIDDEN", warning = "ERR_K_WARNING" }

-- chemins courts : CorpUI_Sacs/Sacs/Sacs.lua:12 au lieu de
-- [string "@Interface/AddOns/CorpUI_Sacs/Sacs/Sacs.lua"]:12
local function tidy(s)
    s = s:gsub("\\", "/")
    s = s:gsub('%[string "@?([^"]*)"%]', "%1")
    s = s:gsub("=%[C%]", "[C]")
    s = s:gsub("=%(tail call%)", "(tail call)")
    s = s:gsub("Interface/AddOns/", "")
    s = s:gsub(FENCE, "'''")
    return s
end

-- coupe a n octets sans casser un caractere UTF-8
local function cut(s, n)
    if #s <= n then return s end
    local i = n
    while i > 0 and (s:byte(i + 1) or 0) >= 0x80 and s:byte(i + 1) < 0xC0 do i = i - 1 end
    return s:sub(1, i) .. "…"
end

-- lignes d un texte (pile, locales), raccourcies ; sans les temporaires
local function lines(s, skipTemp)
    local out = {}
    if type(s) ~= "string" or s == "" then return out end
    for line in s:gmatch("[^\n]+") do
        if not (skipTemp and line:find("(*temporary)", 1, true)) then out[#out + 1] = tidy(line) end
    end
    return out
end

local function addonApi(name)
    return (C_AddOns and C_AddOns[name]) or _G[name]
end

-- addons charges en plus de CorpUI, et modules CorpUI coupes
local function addonsLine()
    local num, info, isOn = addonApi("GetNumAddOns"), addonApi("GetAddOnInfo"), addonApi("IsAddOnLoaded")
    if not (num and info and isOn) then return nil end
    local ok, n = pcall(num)
    local others, off = {}, {}
    for i = 1, ok and tonumber(n) or 0 do
        local okI, name = pcall(info, i)
        if okI and type(name) == "string" and not name:find("^Blizzard_") then
            local okL, on = pcall(isOn, name)
            on = okL and on
            if name:find("^CorpUI") then
                if not on then off[#off + 1] = (name:gsub("^CorpUI_", "")) end
            elseif on then
                others[#others + 1] = name
            end
        end
    end
    local function list(t, max)
        if #t <= max then return table.concat(t, ", ") end
        return table.concat(t, ", ", 1, max) .. " +" .. (#t - max)
    end
    local s = string.format(L.ERR_R_ADDONS, #others > 0 and list(others, 15) or L.ERR_R_NONE)
    if #off > 0 then s = s .. " · " .. string.format(L.ERR_R_OFF, list(off, 15)) end
    return s
end

local function aboutLine(e)
    local c = e.ctx or {}
    local parts = {}
    local function add(s) if s and s ~= "" then parts[#parts + 1] = s end end
    local ok, ver, build = pcall(GetBuildInfo)
    if ok and ver then add("WoW " .. tostring(ver) .. (build and (" (" .. tostring(build) .. ")") or "")) end
    add(GetLocale and GetLocale())
    if c.class then add(c.class .. (c.level and (" " .. c.level) or "")) end
    add(c.zone)
    if c.combat ~= nil then add(c.combat and L.ERR_R_COMBAT or L.ERR_R_PEACE) end
    if c.group == "raid" then
        add(string.format(L.ERR_R_RAID, c.size or 0))
    elseif c.group == "party" then
        add(string.format(L.ERR_R_PARTY, c.size or 0))
    elseif c.combat ~= nil then
        add(L.ERR_R_SOLO)
    end
    return table.concat(parts, " · ")
end

local function whenLine(e)
    local s = string.format(L.ERR_WHEN, e.count or 1, stamp(e.first), stamp(e.last))
    if e.session == sessionId and e.sessCount and e.sessCount ~= (e.count or 1) then
        s = s .. " · " .. string.format(L.ERR_R_SESSION, e.sessCount)
    end
    return s
end

local function report(e, full)
    local ver = e.ctx and e.ctx.ver
    local top = table.concat({
        string.format("**CorpUI%s** · %s", ver and (" " .. ver) or "", L[KIND[e.kind] or "ERR_K_ERROR"]),
        "-# " .. aboutLine(e),
        "-# " .. whenLine(e),
        FENCE .. "lua",
    }, "\n")
    local foot = addonsLine()
    local bottom = FENCE .. (foot and ("\n-# " .. foot) or "")
    local note = "-- " .. L.ERR_R_CUT
    -- place pour le bloc de code (une fin de ligne par ligne)
    local room = full and math.huge or (DISCORD_MAX - #top - #bottom - 2 - #note - 1)
    local body, used, cutOff = {}, 0, false
    local function put(s)
        if used + #s + 1 > room then cutOff = true return false end
        body[#body + 1] = s
        used = used + #s + 1
        return true
    end
    local msg = tidy(e.raw or e.msg or "?")
    if not full then msg = cut(msg, math.min(600, math.max(room - 40, 40))) end
    put(msg)
    local stack, locs = lines(e.stack), lines(e.locals, true)
    if #stack == 0 then
        put("-- " .. L.ERR_R_NOSTACK)
    else
        put("")
        put("-- " .. L.ERR_STACK)
        for _, s in ipairs(stack) do if not put(s) then break end end
    end
    if #locs > 0 and not cutOff then
        put("")
        put("-- " .. L.ERR_LOCALS)
        for _, s in ipairs(locs) do if not put(s) then break end end
    end
    if cutOff then body[#body + 1] = note end
    return top .. "\n" .. table.concat(body, "\n") .. "\n" .. bottom
end

local refreshWindow

local function buildWindow()
    local C = ns.COLORS
    win = CreateFrame("Frame", "CorpUIErrors", UIParent, "BackdropTemplate")
    win:SetSize(640, 420)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    ns.UI.SetBackdrop(win, 0.97)
    ns.UI.Shadow(win, 5)
    win:Hide()

    local title = win:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 14)
    title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText(L.ERR_TITLE)
    local close = ns.UI.Button(win, "×", 24, function() win:Hide() end)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -6, -6)

    -- navigation
    win.prev = ns.UI.Button(win, "<", 26, function() view.index = (view.index or 1) - 1 refreshWindow() end)
    win.prev:SetSize(26, 22)
    win.prev:SetPoint("TOPLEFT", 10, -32)
    win.page = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.page:SetPoint("LEFT", win.prev, "RIGHT", 8, 0)
    win.page:SetWidth(150)
    win.next = ns.UI.Button(win, ">", 26, function() view.index = (view.index or 0) + 1 refreshWindow() end)
    win.next:SetSize(26, 22)
    win.next:SetPoint("LEFT", win.page, "RIGHT", 8, 0)
    win.scope = ns.UI.Button(win, "", 120, function()
        view.all = not view.all
        view.index = nil
        refreshWindow()
    end)
    win.scope:SetPoint("LEFT", win.next, "RIGHT", 12, 0)
    win.clear = ns.UI.Button(win, L.ERR_CLEAR, 130, function()
        if GetTime() > sureUntil then
            sureUntil = GetTime() + 3
            refreshWindow()
            C_Timer.After(3.05, function() if win:IsShown() then refreshWindow() end end)
            return
        end
        sureUntil = 0
        if db then wipe(db.list) end
        view.index = nil
        refreshWindow()
        paintButton()
    end)
    win.clear:SetPoint("RIGHT", close, "LEFT", -8, 0)

    -- texte selectionnable : le rapport pour Discord
    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -62)
    scroll:SetPoint("BOTTOMRIGHT", -30, 36)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(590)
    edit:SetScript("OnEscapePressed", function() win:Hide() end)
    -- lecture seule : une frappe remet le texte
    edit:SetScript("OnTextChanged", function(self, user)
        if user then self:SetText(self.shown or "") end
    end)
    scroll:SetScrollChild(edit)
    win.edit, win.scroll = edit, scroll

    -- copier : tout selectionner, Ctrl+C reste au joueur (le presse-papiers
    -- est reserve a Blizzard) ; format Discord (2000 caracteres) ou complet
    win.copy = ns.UI.Button(win, L.ERR_COPY, 110, function()
        edit:SetFocus()
        edit:HighlightText()
        win.hint:SetText(L.ERR_COPIED)
    end)
    win.copy:SetSize(110, 22)
    win.copy:SetPoint("BOTTOMRIGHT", -10, 8)
    win.format = ns.UI.Button(win, "", 150, function()
        view.full = not view.full
        refreshWindow()
    end)
    win.format:SetSize(150, 22)
    win.format:SetPoint("RIGHT", win.copy, "LEFT", -8, 0)
    win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.hint:SetPoint("BOTTOMLEFT", 10, 13)
    win.hint:SetPoint("RIGHT", win.format, "LEFT", -8, 0)
    win.hint:SetJustifyH("LEFT")
    win:SetScript("OnShow", function() refreshWindow() end)
    win:SetScript("OnHide", function() edit:ClearFocus() end)
end

refreshWindow = function()
    if not win then return end
    local list = currentList()
    local n = #list
    if not view.index or view.index > n then view.index = n end
    if view.index < 1 then view.index = math.min(1, n) end
    local e = list[view.index]
    win.page:SetText(n > 0 and string.format(L.ERR_PAGE, view.index, n) or "")
    win.prev:SetEnabled(view.index > 1)
    win.next:SetEnabled(view.index < n)
    win.scope:SetText(view.all and L.ERR_ALL or L.ERR_SESSION)
    win.clear:SetText(GetTime() < sureUntil and L.ERR_CLEAR_SURE or L.ERR_CLEAR)
    win.clear:SetEnabled(db ~= nil and #db.list > 0)
    win.format:SetText(view.full and L.ERR_FMT_FULL or L.ERR_FMT_DISCORD)
    win.copy:SetEnabled(e ~= nil)
    local text = e and report(e, view.full) or L.ERR_NONE
    -- caracteres (UTF-8), comme les compte Discord
    win.hint:SetText(e and string.format(L.ERR_COPY_HINT, select(2, text:gsub("[^\128-\191]", ""))) or "")
    win.edit.shown = text
    win.edit:SetText(text)
    win.edit:HighlightText(0, 0)
    win.edit:SetCursorPosition(0)
    win.scroll:SetVerticalScroll(0)
end

function ns.ErrorsToggle(show)
    if not win then buildWindow() end
    if win:IsShown() and not show then win:Hide() return end
    view.index = nil
    win:Show()
    refreshWindow()
end

-- nouvelle erreur, ou une deja vue de plus
notify = function(e, isNew)
    if isNew or e.sessCount == 1 then pulseUntil = GetTime() + 4 end
    paintButton()
    if win and win:IsShown() then refreshWindow() end
    if db and db.opt.chat and (isNew or e.sessCount == 1) then
        ns.Say(string.format(L.ERR_CHAT_NEW, firstLine(e.msg)))
    end
end

---------------------------------------------------------------------------
-- Reglages (/corp erreurs options)
---------------------------------------------------------------------------

local panel

local function buildPanel()
    panel = ns.UI.Window("CorpUIErrorsOptions", ns.TITLE .. " - " .. L.MOD_ERRORS, nil, 440, 220)
    local form = ns.UI.Form(panel, -34, function() paintButton() end)
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y)
    status:SetWidth(424)
    status:SetJustifyH("LEFT")
    form.y = form.y - 34
    form:Check(L.ERR_OPT_ALWAYS, function() return db.opt.always end, function(v) db.opt.always = v end)
    form:Check(L.ERR_OPT_CHAT, function() return db.opt.chat end, function(v) db.opt.chat = v end)
    local open = ns.UI.Button(panel, L.ERR_OPEN, 160, function() ns.ErrorsToggle(true) end)
    open:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y - 6)
    form.y = form.y - 36
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y)
    hint:SetWidth(424)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.ERR_HINT)
    table.insert(form.refreshers, function()
        local unique, times = sessionTotals()
        local s = string.format(L.ERR_TIP_COUNT, unique, times) .. "  ·  " .. string.format(L.ERR_STORED, db and #db.list or 0)
        if not installed then s = s .. "\n|cffff8040" .. L.ERR_NOT_INSTALLED .. "|r" end
        status:SetText(s)
    end)
    panel:HookScript("OnShow", function() form:Refresh() end)
end

local function openPanel()
    if not db then return end
    if not panel then buildPanel() end
    ns.ShowPanel(panel)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGIN" then return end
    if ns.ModuleOff("erreurs", ev) then
        -- module coupe : le gestionnaire du jeu revient, avec nos erreurs
        if installed and blizzHandler and seterrorhandler then
            pcall(seterrorhandler, blizzHandler)
            installed = false
            for _, e in ipairs(pending) do pcall(blizzHandler, e.msg) end
        end
        pending = {}
        pcall(cap.UnregisterAllEvents, cap)
        return
    end
    local root = ns.InitRoot()
    if type(root.errors) ~= "table" then root.errors = {} end
    db = root.errors
    if type(db.list) ~= "table" then db.list = {} end
    if type(db.opt) ~= "table" then db.opt = {} end
    db.session = (tonumber(db.session) or 0) + 1
    sessionId = db.session
    -- erreurs du chargement
    local early = pending
    pending = {}
    for _, e in ipairs(early) do store(e) end
    -- sans minicarte CorpUI, l icone est libre
    C_Timer.After(2, function()
        if not btn then freeButton() end
        paintButton()
    end)
end)
ev:RegisterEvent("PLAYER_LOGIN")

ns.RegisterModule({
    command = "erreurs",
    alias = "bugs",
    panelName = "CorpUIErrorsOptions",
    icon = "Interface\\Icons\\Spell_Nature_InsectSwarm",
    title = function() return L.MOD_ERRORS end,
    desc = function() return L.ERR_DESC end,
    Slash = function(rest)
        rest = strlower(strtrim(rest or ""))
        if rest == "options" or rest == "config" then openPanel() else ns.ErrorsToggle() end
    end,
    Open = openPanel,
})

-- banc d essai
ns._errors = { store = store, onError = onError, list = function() return db and db.list end,
               installed = function() return installed end, button = function() return btn end,
               session = function() return sessionId end, paint = paintButton,
               report = function(e, full) return report(e, full) end, onAction = onAction }
