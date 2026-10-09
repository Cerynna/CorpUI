--[[--------------------------------------------------------------------------
    CorpUI - module Invitations : inviter sur mot cle

    Un joueur ecrit un mot cle ("+1" par defaut, plusieurs possibles) : il
    est invite dans le groupe tout seul.
      - ou l on ecoute : chuchotements (par defaut), canal de guilde, dire
        et crier (reglages) ;
      - membres de la guilde seulement (reglage, actif par defaut) :
        C_GuildInfo.MemberExistsByName, sinon la liste de la guilde ;
      - message = exactement un mot cle (par defaut) ou le contenant comme
        mot entier ; majuscules et espaces autour ignores ;
      - on n invite que si on le peut : seul, chef du groupe, ou assistant
        en raid ; raid plein ou joueur deja dans le groupe : rien ; un meme
        joueur n est pas traite deux fois en 15 s ;
      - groupe de 5 : le jeu demande lui-meme de passer en raid (le passage
        en raid est interdit aux addons : ConvertToRaid HasRestrictions) ;
      - messages masques par le jeu (verrou de discussion) : ignores ;
      - /corp inv on | off : activer ou couper vite.
    C_PartyInfo.InviteUnit n est pas restreinte ; les noms viennent tels
    quels de CHAT_MSG_* (cible valide, noms uniques regionaux compris) ;
    aucun code de Blizzard n est touche.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local issecret = issecretvalue or function() return false end

local COOLDOWN = 15
local MAX_KEYWORDS = 10
local MAX_LEN = 24

local db
local recent = {}   -- joueur -> GetTime() de la derniere demande traitee

local function str(v)
    if issecret(v) or type(v) ~= "string" then return nil end
    return v
end

local function yes(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    return ok and not issecret(v) and v and true or false
end

local function count(fn)
    if type(fn) ~= "function" then return 0 end
    local ok, v = pcall(fn)
    if not ok or issecret(v) or type(v) ~= "number" then return 0 end
    return v
end

---------------------------------------------------------------------------
-- Mots cles
---------------------------------------------------------------------------

local function norm(s) return strlower(strtrim(s or "")) end

-- message en mots separes par une espace (espaces et ponctuation)
local function words(s) return " " .. (norm(s):gsub("[%s,;:%.!%?]+", " ")) .. " " end

-- mot cle trouve dans le message (nil sinon)
local function matches(text)
    local t = norm(text)
    if t == "" then return nil end
    local w = db.match == "word" and words(text)
    for _, kw in ipairs(db.keywords) do
        local k = norm(kw)
        if k ~= "" then
            if t == k then return kw end
            if w and w:find(words(k), 1, true) then return kw end
        end
    end
    return nil
end

-- rend nil si accepte, sinon le message a afficher
local function addKeyword(text)
    local k = strtrim(text or "")
    if k == "" then return nil end
    if #k > MAX_LEN then k = k:sub(1, MAX_LEN) end
    for _, kw in ipairs(db.keywords) do
        if norm(kw) == norm(k) then return nil end
    end
    if #db.keywords >= MAX_KEYWORDS then return string.format(L.INV_TOO_MANY, MAX_KEYWORDS) end
    table.insert(db.keywords, k)
    return nil
end

---------------------------------------------------------------------------
-- Qui inviter
---------------------------------------------------------------------------

local function inGuild(sender)
    if not yes(IsInGuild) then return false end
    if C_GuildInfo and C_GuildInfo.MemberExistsByName then
        local ok, v = pcall(C_GuildInfo.MemberExistsByName, sender)
        if ok and not issecret(v) and v then return true end
    end
    -- repli : la liste de la guilde (noms ramenes a la meme ecriture)
    local who = ns.Names.Sender(sender)
    for i = 1, count(GetNumGuildMembers) do
        local ok, n = pcall(GetGuildRosterInfo, i)
        n = ok and str(n) or nil
        if n and ns.Names.Sender(n) == who then return true end
    end
    return false
end

local function inMyGroup(who)
    local raid = yes(IsInRaid)
    local n = count(GetNumGroupMembers)
    -- en groupe, party1..4 (le joueur compte dans le total)
    local last = raid and n or math.max(0, n - 1)
    for i = 1, last do
        if ns.Names.Unit((raid and "raid" or "party") .. i) == who then return true end
    end
    return false
end

-- "ok", "notlead" ou "full"
local function groupState()
    if not yes(IsInGroup) then return "ok" end
    local raid = yes(IsInRaid)
    local lead = yes(UnitIsGroupLeader, "player") or (raid and yes(UnitIsGroupAssistant, "player"))
    if not lead then return "notlead" end
    if raid and count(GetNumGroupMembers) >= 40 then return "full" end
    return "ok"
end

local function tell(fmt, ...)
    if db.announce then ns.Say(string.format(fmt, ...)) end
end

-- un message recu : text et sender tels que CHAT_MSG_* les donne
local function handle(text, sender, fromGuild)
    if not db or not db.enabled then return end
    text, sender = str(text), str(sender)
    if not text or not sender then return end
    local kw = matches(text)
    if not kw then return end
    local who = ns.Names.Sender(sender)
    if not who or who == ns.Names.Me() then return end
    local now = GetTime()
    if recent[who] and now - recent[who] < COOLDOWN then return end
    recent[who] = now
    local name = ns.Names.Display(who)
    if db.guildOnly and not fromGuild and not inGuild(sender) then
        tell(L.INV_NOT_GUILD, name)
        return
    end
    if inMyGroup(who) then return end
    local state = groupState()
    if state == "notlead" then
        tell(L.INV_NOT_LEADER, name, kw)
        return
    elseif state == "full" then
        tell(L.INV_FULL, name)
        return
    end
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if fn and pcall(fn, sender) then tell(L.INV_SENT, name, kw) end
end

---------------------------------------------------------------------------
-- Reglages (/corp inv)
---------------------------------------------------------------------------

local panel, refreshList

local function buildPanel()
    panel = ns.UI.Window("CorpUIInviteOptions", ns.TITLE .. " - " .. L.MOD_INV, nil, 440, 430)
    local form = ns.UI.Form(panel, -34)
    form:Check(L.INV_OPT_ENABLE, function() return db.enabled end, function(v) db.enabled = v end)
    form:Check(L.INV_OPT_GUILD, function() return db.guildOnly end, function(v) db.guildOnly = v end)
    form:Check(L.INV_OPT_ANNOUNCE, function() return db.announce end, function(v) db.announce = v end)
    form:Header(L.INV_LISTEN)
    form:Columns(3)
    form:Check(L.INV_CH_WHISPER, function() return db.whisper end, function(v) db.whisper = v end)
    form:Check(L.INV_CH_GUILD, function() return db.guild end, function(v) db.guild = v end)
    form:Check(L.INV_CH_SAY, function() return db.say end, function(v) db.say = v end)
    form:EndColumns()
    form:Cycle(L.INV_MATCH, { "exact", "word" }, { exact = L.INV_MATCH_EXACT, word = L.INV_MATCH_WORD },
        function() return db.match end, function(v) db.match = v end)
    form:Header(L.INV_KEYWORDS)
    -- saisie + Ajouter
    local box = ns.UI.EditBox(panel, 200, 22)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y)
    box:SetMaxLetters(MAX_LEN)
    local function submit()
        local err = addKeyword(box:GetText())
        if err then ns.Say(err) end
        box:SetText("")
        box:ClearFocus()
        refreshList()
    end
    local add = ns.UI.Button(panel, L.INV_ADD, 90, submit)
    add:SetPoint("LEFT", box, "RIGHT", 6, 0)
    box:SetScript("OnEnterPressed", submit)
    -- liste : deux colonnes de 5
    local rows = {}
    local top = form.y - 32
    for i = 1, MAX_KEYWORDS do
        local col, row = math.floor((i - 1) / 5), (i - 1) % 5
        local r = CreateFrame("Frame", nil, panel)
        r:SetSize(200, 22)
        r:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + col * 212, top - row * 24)
        local del = ns.UI.Button(r, "×", 22, function()
            table.remove(db.keywords, i)
            refreshList()
        end)
        del:SetPoint("LEFT", 0, 0)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.text:SetPoint("LEFT", del, "RIGHT", 8, 0)
        r.text:SetPoint("RIGHT", 0, 0)
        r.text:SetJustifyH("LEFT")
        rows[i] = r
    end
    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, top - 4)
    empty:SetText(L.INV_EMPTY)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, top - 5 * 24 - 8)
    hint:SetWidth(424)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.INV_HINT)
    function refreshList()
        for i, r in ipairs(rows) do
            local kw = db.keywords[i]
            r.text:SetText(kw or "")
            r:SetShown(kw ~= nil)
        end
        empty:SetShown(#db.keywords == 0)
    end
    panel:HookScript("OnShow", function()
        form:Refresh()
        refreshList()
    end)
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
ev:SetScript("OnEvent", function(_, event, text, sender)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        if type(root.invite) ~= "table" then root.invite = {} end
        db = root.invite
        if db.enabled == nil then db.enabled = true end
        if type(db.keywords) ~= "table" then db.keywords = { "+1" } end
        if db.guildOnly == nil then db.guildOnly = true end
        if db.announce == nil then db.announce = true end
        if db.whisper == nil then db.whisper = true end
        if db.guild == nil then db.guild = false end
        if db.say == nil then db.say = false end
        if db.match ~= "exact" and db.match ~= "word" then db.match = "exact" end
        -- liste de la guilde a jour (repli de MemberExistsByName)
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        return
    end
    if not db then return end
    if event == "CHAT_MSG_WHISPER" then
        if db.whisper then handle(text, sender, false) end
    elseif event == "CHAT_MSG_GUILD" then
        if db.guild then handle(text, sender, true) end
    elseif event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL" then
        if db.say then handle(text, sender, false) end
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_WHISPER", "CHAT_MSG_GUILD", "CHAT_MSG_SAY", "CHAT_MSG_YELL" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.RegisterModule({
    command = "inv",
    alias = "invite",
    panelName = "CorpUIInviteOptions",
    icon = "Interface\\Icons\\Spell_Holy_PrayerofSpirit",
    title = function() return L.MOD_INV end,
    desc = function() return L.INV_DESC end,
    Slash = function(rest)
        rest = strlower(strtrim(rest or ""))
        if not db then return end
        if rest == "on" or rest == "off" then
            db.enabled = rest == "on"
            ns.Say(db.enabled and L.INV_ON or L.INV_OFF)
            ns.Changed()
        else
            openPanel()
        end
    end,
    Open = openPanel,
})

-- banc d essai
ns._invite = { handle = handle, matches = matches, addKeyword = addKeyword, groupState = groupState,
               state = function() return db end, openPanel = openPanel }
