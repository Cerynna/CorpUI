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
        deja vue (meme message, meme premiere ligne de pile) : elle compte
        une fois de plus et repasse en tete ; valeur secrete : "(illisible)" ;
      - aussi notes : actions bloquees ou interdites a un addon
        (ADDON_ACTION_BLOCKED / FORBIDDEN) et avertissements Lua ;
      - icone dans la barre d icones de la minicarte (a cote du suivi et du
        courrier), avec le nombre d erreurs de la session ; clic : la
        fenetre (une erreur par page, cette session ou toutes, texte
        selectionnable pour Ctrl+C) ; sans minicarte CorpUI : icone libre
        au coin de la carte ;
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

local function store(e)
    if not db then
        if #pending < MAX_ERRORS then pending[#pending + 1] = e end
        return
    end
    local key = (e.msg or "") .. "\n" .. firstLine(e.stack)
    local list = db.list
    for i = #list, 1, -1 do
        local x = list[i]
        if x.key == key then
            x.count = (x.count or 1) + 1
            x.last = e.time
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

local function record(msg, stack, locals)
    local m = safeText(msg) or "?"
    local st = safeText(stack)
    local lo = safeText(locals)
    if lo and lo ~= L.ERR_SECRET then lo = lo:gsub("|([kK])", "%1") end
    -- journal du jeu (Logs\General.log), comme le gestionnaire de Blizzard
    if C_Log and C_Log.LogErrorMessage and readable(msg) and (stack == nil or readable(stack)) then
        pcall(C_Log.LogErrorMessage, string.format("Lua Error: %s\n%s", tostring(msg), tostring(stack or "")))
    end
    return store({ msg = m, stack = st, locals = lo, time = time(), kind = "error" })
end

-- avalanche (la meme erreur a chaque image) : dans la seconde qui suit,
-- elle est seulement comptee, sans relire pile et locales (couteux)
local stormMsg, stormAt, stormEntry = nil, 0, nil
local function onError(msg)
    if handling then return end
    handling = true
    local now = GetTime()
    local plain = type(msg) == "string" and not issecret(msg) and msg or nil
    if plain and plain == stormMsg and stormEntry and now - stormAt < 1 and now >= stormAt then
        stormEntry.count = (stormEntry.count or 1) + 1
        stormEntry.sessCount = (stormEntry.sessCount or 1) + 1
        stormEntry.last = time()
        stormAt = now
        if notify then pcall(notify, stormEntry, false) end
        handling = false
        return
    end
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

-- actions bloquees ou interdites, avertissements Lua
local cap = CreateFrame("Frame")
cap:SetScript("OnEvent", function(_, event, a, b)
    local now = time()
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local fmt = event == "ADDON_ACTION_BLOCKED" and L.ERR_BLOCKED or L.ERR_FORBIDDEN
        store({ msg = string.format(fmt, safeText(a) or "?", safeText(b) or "?"), time = now, kind = "blocked" })
    elseif event == "LUA_WARNING" then
        store({ msg = string.format(L.ERR_WARNING, safeText(b) or safeText(a) or "?"), time = now, kind = "warning" })
    end
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

local view = { all = false, index = nil }
local sureUntil = 0

local function currentList()
    if view.all then return db and db.list or {} end
    return sessionList()
end

local function stamp(t)
    return t and date(L.ERR_DATE, t) or "?"
end

local function errorText(e)
    local parts = { e.msg or "?", "" }
    parts[#parts + 1] = string.format(L.ERR_WHEN, e.count or 1, stamp(e.first), stamp(e.last))
    if e.stack and e.stack ~= "" then
        parts[#parts + 1] = ""
        parts[#parts + 1] = L.ERR_STACK
        parts[#parts + 1] = e.stack
    end
    if e.locals and e.locals ~= "" then
        parts[#parts + 1] = ""
        parts[#parts + 1] = L.ERR_LOCALS
        parts[#parts + 1] = e.locals
    end
    return table.concat(parts, "\n")
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

    -- texte selectionnable
    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -62)
    scroll:SetPoint("BOTTOMRIGHT", -30, 28)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(590)
    edit:SetScript("OnEscapePressed", function() win:Hide() end)
    -- lecture seule : une frappe remet le texte
    edit:SetScript("OnTextChanged", function(self, user)
        if user then self:SetText(self.shown or "") end
    end)
    scroll:SetScrollChild(edit)
    win.edit, win.scroll = edit, scroll
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 10, 9)
    hint:SetText(L.ERR_COPY_HINT)
    win:SetScript("OnShow", function() refreshWindow() end)
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
    local text = e and errorText(e) or L.ERR_NONE
    win.edit.shown = text
    win.edit:SetText(text)
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
               session = function() return sessionId end, paint = paintButton }
