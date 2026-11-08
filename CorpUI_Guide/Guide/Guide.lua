--[[--------------------------------------------------------------------------
    CorpUI - module Guide : choix du guide, calcul, reglages, commandes

    Usage prive (08/11) : donnees de WoW Forever Tools sans licence,
    jamais publiees (Donnees/ ignore par git, CorpUI_Guide hors paquet).

    Par personnage (CorpUIDB.guide.chars[perso]) : guide choisi (sinon
    celui de sa race et de sa classe), avec ou sans donjons, avancement de
    chaque guide (position, etapes cochees a la main).
    Calcul : tout de suite apres un evenement du journal, du niveau ou des
    sorts (au plus 4 fois par seconde) ; la fleche passe au point suivant
    de l etape en arrivant (verifie 2 fois par seconde).

    /corp guide          : ouvrir le guide
    /corp guide options  : reglages
    /corp guide recaler  : se placer apres la derniere quete rendue
    /corp guide diag     : guide, position, conditions de l etape en cours
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local GD = ns.Guide
local num, call = GD.num, GD.call

local db
local dirty, lastRun = true, 0
local tgt = { k = nil, i = 1 }

local function charDB()
    local k = ns.CharKey()
    db.chars = type(db.chars) == "table" and db.chars or {}
    if type(db.chars[k]) ~= "table" then db.chars[k] = {} end
    return db.chars[k]
end

-- guide du personnage (choisi, sinon conseille) et son avancement
local function pickGuide()
    GD.g, GD.prog = nil, nil
    if not GD.Data() then return end
    local c = charDB()
    local key = c.guide and GD.Get(c.guide) and c.guide or GD.Pick(c.dungeons)
    key = key and GD.Variant(key, c.dungeons) or nil
    local g = GD.Get(key)
    if not g then return end
    GD.g = g
    GD.prog = GD.Prog(c, g.k)
    -- premier passage dans ce guide : place apres les quetes deja rendues
    if GD.prog.new then
        GD.prog.new = nil
        GD.CatchUp(g, GD.prog)
    end
end

-- point de la fleche : coordonnees de l etape en cours, la suivante en arrivant
local function point(me)
    local g, prog = GD.g, GD.prog
    if not g or prog.p > #g.e then return nil end
    local st, e = GD.StepAt(g, prog.p, prog.s)
    local k = GD.Key(prog.p, prog.s)
    if tgt.k ~= k then tgt.k, tgt.i = k, 1 end
    if not (st and e and #st.coords > 0) then return nil end
    local map = (e[2] and e[2] > 0) and e[2] or (me and me.map)
    if not map then return nil end
    local function at(i)
        local c = st.coords[i]
        return { map = map, x = c[1] / 100, y = c[2] / 100, label = c[3] }
    end
    tgt.i = math.max(1, math.min(tgt.i, #st.coords))
    local a = at(tgt.i)
    if tgt.i < #st.coords then
        local d = GD.Distance(me, a)
        if d and d < GD.ARRIVED then
            tgt.i = tgt.i + 1
            a = at(tgt.i)
        end
    end
    local label = a.label and GD.Plain(a.label) or e[1]
    a.title = (#st.coords > 1) and string.format("%s (%d/%d)", label, tgt.i, #st.coords) or label
    return a
end

local function aim()
    if not db then return end
    local a = point(GD.Player())
    GD.target = a
    GD.SetArrow(a, db)
    GD.SetNative(a, db.native)
end

local function refresh()
    if not db then return end
    lastRun = GetTime()
    dirty = false
    if GD.g and GD.prog then GD.Advance(GD.g, GD.prog) end
    GD.DrawTracker()
    aim()
    if GD.RefreshWindow then GD.RefreshWindow() end
end
GD.Refresh = function() if db then refresh() end end
function GD.Dirty() dirty = true end

---------------------------------------------------------------------------
-- Actions (suivi, fenetre, commandes)
---------------------------------------------------------------------------

function GD.ValidateStep()
    if not GD.g then return end
    GD.Validate(GD.g, GD.prog)
    refresh()
end

function GD.BackStep()
    if not GD.g then return end
    GD.Back(GD.g, GD.prog)
    refresh()
end

function GD.GoToStep(p, s)
    if not GD.g then return end
    GD.GoTo(GD.g, GD.prog, p, s)
    refresh()
end

function GD.ToggleStep(p, s)
    if not GD.g then return end
    GD.Toggle(GD.g, GD.prog, p, s)
    refresh()
end

-- fleche sur le point i de l etape en cours (clic sur des coordonnees)
function GD.Aim(i)
    if not GD.prog then return end
    tgt.k, tgt.i = GD.Key(GD.prog.p, GD.prog.s), i
    aim()
end

-- changer de guide (cle de base, sans "-dungeons")
function GD.SetGuide(key)
    local c = charDB()
    c.guide = key
    pickGuide()
    refresh()
end

function GD.SetDungeons(on)
    local c = charDB()
    c.dungeons = on and true or false
    if GD.g then c.guide = GD.g.k:gsub("%-dungeons$", "") end
    pickGuide()
    refresh()
end
function GD.Dungeons() return db and charDB().dungeons == true end

function GD.CatchUpNow()
    if not GD.g then return end
    local n = GD.CatchUp(GD.g, GD.prog)
    ns.Say(string.format(L.GUIDE_CAUGHT_UP, GD.Index(GD.g, math.min(GD.prog.p, #GD.g.e), GD.prog.s), GD.Total(GD.g), n))
    refresh()
end

function GD.ResetProgress()
    if not GD.g then return end
    local c = charDB()
    c.prog[GD.g.k] = nil
    GD.prog = GD.Prog(c, GD.g.k)
    GD.prog.new = nil
    refresh()
end

---------------------------------------------------------------------------
-- Diagnostic
---------------------------------------------------------------------------

local function diag()
    local d = GD.Data()
    if not d then
        ns.Say(L.GUIDE_NO_DATA)
        return
    end
    local who = GD.Who()
    ns.Say(string.format("guide : %d guides, %d parties ; perso %s %s %s (%s)", #d.G, #d.E,
        tostring(who.raceToken), tostring(who.classToken), tostring(who.faction), tostring(d.LANG)))
    local g, prog = GD.g, GD.prog
    if not g then
        ns.Say("  aucun guide pour ce personnage")
        return
    end
    ns.Say(string.format("  %s (%s), partie %d/%d, etape %d/%d%s", GD.Label(g), g.k, math.min(prog.p, #g.e), #g.e,
        GD.Index(g, math.min(prog.p, #g.e), prog.s), GD.Total(g), prog.hold and " (choisie a la main)" or ""))
    local st, e = GD.StepAt(g, prog.p, prog.s)
    if st then
        ns.Say(string.format("  carte %s (%s), %d point(s), %d condition(s)", tostring(e[2]), tostring(e[3]), #st.coords, #st.conds))
        local NAMES = { a = "prendre", t = "rendre", o = "faire", x = "abandonner", l = "sort", v = "niveau" }
        for _, c in ipairs(st.conds) do
            ns.Say(string.format("    %s %d : %s", NAMES[c[1]] or c[1], c[2], GD.CondOk(c) and "ok" or "pas encore"))
        end
    end
    local me = GD.Player()
    ns.Say(string.format("  joueur : carte %s, %s ; fleche : %s", tostring(me and me.map),
        (me and me.x) and string.format("%.1f, %.1f", me.x * 100, me.y * 100) or "?",
        GD.target and string.format("%d %.1f, %.1f", GD.target.map, GD.target.x * 100, GD.target.y * 100) or "aucune"))
end

---------------------------------------------------------------------------
-- Reglages
---------------------------------------------------------------------------

local win

local function buildOptions()
    win = ns.UI.Window("CorpUIGuideOptions", ns.TITLE .. " - " .. L.MOD_GUIDE, nil, 440, 320)
    local form = ns.UI.Form(win, -34)
    form:Header(L.GUIDE_H_TRACKER)
    form:Check(L.GUIDE_OPT_SHOW, function() return db.show end, function(v) db.show = v refresh() end)
    form:Number(L.GUIDE_OPT_AHEAD, function() return db.ahead end, function(v) db.ahead = v refresh() end, 0, 4)
    form:Number(L.GUIDE_OPT_WIDTH, function() return db.width end, function(v) db.width = v refresh() end, 240, 480, 20)
    form:Number(L.GUIDE_OPT_ALPHA, function() return math.floor((db.alpha or 0.75) * 100 + 0.5) end,
        function(v) db.alpha = v / 100 refresh() end, 0, 100, 5)
    form:Header(L.GUIDE_H_ARROW)
    form:Check(L.GUIDE_OPT_ARROW, function() return db.arrow end, function(v) db.arrow = v refresh() end)
    form:Number(L.GUIDE_OPT_ARROW_SIZE, function() return db.arrowScale end, function(v)
        db.arrowScale = v
        GD.ArrowScale()
    end, 50, 200, 10)
    form:Check(L.GUIDE_OPT_NATIVE, function() return db.native end, function(v)
        db.native = v
        if not v then GD.SetNative(nil, false) end
        refresh()
    end)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.GUIDE_HINT)
    local open = ns.UI.Button(win, L.GUIDE_OPEN, 180, function() GD.ToggleWindow(true) end)
    open:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    win:SetHeight(-form.y + 110)
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function openOptions()
    if not db then return end
    if not win then buildOptions() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("guide", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.guide = type(root.guide) == "table" and root.guide or {}
        db = root.guide
        if db.show == nil then db.show = true end
        if db.arrow == nil then db.arrow = true end
        -- repere de Blizzard : ses gestionnaires tourneraient depuis notre appel
        if db.native == nil then db.native = false end
        db.ahead = db.ahead or 2
        db.width = db.width or 320
        db.alpha = db.alpha or 0.75
        db.arrowScale = db.arrowScale or 100
        GD.who = GD.Who()
        GD.BuildTracker(db)
        pickGuide()
        -- deverrouillage : suivi et fleche en apercu
        ns.Listen(function() if db then GD.DrawTracker() GD.SetArrow(GD.target, db) end end)
        dirty = true
        return
    end
    if not db then return end
    if event == "QUEST_TURNED_IN" then
        -- quete marquee rendue un peu apres l evenement
        C_Timer.After(1, function() dirty = true end)
    end
    dirty = true
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
                     "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
                     "ZONE_CHANGED_NEW_AREA" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- calcul apres un evenement (au plus 4 fois par seconde) ; fleche : point
-- suivant de l etape en arrivant (2 fois par seconde)
ns.Every(0.25, function()
    if not db then return end
    if dirty then
        local ok, err = pcall(refresh)
        if not ok then geterrorhandler()(err) end
    elseif GetTime() - lastRun >= 0.5 then
        lastRun = GetTime()
        local ok, err = pcall(aim)
        if not ok then geterrorhandler()(err) end
    end
end, "Guide", "guide")

-- banc d essai
function GD._state() return { db = db, dirty = dirty, tgt = tgt, char = db and charDB() } end

ns.RegisterModule({
    command = "guide",
    alias = "lvl",
    panelName = "CorpUIGuideOptions",
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    title = function() return L.MOD_GUIDE end,
    desc = function() return L.GUIDE_DESC end,
    Slash = function(input)
        local cmd = strlower(strtrim(input or ""))
        if not db then return end
        if cmd == "diag" then diag() return end
        if cmd == "options" or cmd == "config" then openOptions() return end
        if cmd == "recaler" or cmd == "catchup" then GD.CatchUpNow() return end
        GD.ToggleWindow()
    end,
    Open = openOptions,
})
