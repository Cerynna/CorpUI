--[[--------------------------------------------------------------------------
    CorpUI - editeur des cadres (page "Cadres d unite")

    Une liste deroulante de tous les cadres : on en choisit un et on regle
    tout ce qui le concerne au meme endroit. Chaque module fournit ses
    sections (ns.FramesOpt.*, construites dans un sous-panneau) :
      Tous les cadres : reglages communs (cadres de Blizzard, echelle,
                        barres de sort, listes de filtres d auras)
      Joueur          : affichage, apparence et textes, barre de sort,
                        buffs et debuffs, ressources, centre, totems,
                        minuteur de coups blancs
      Cible           : affichage, apparence et textes, barre de sort, auras
      Cible de la cible, Familier : affichage, apparence et textes
      Focalisation    : affichage, apparence et textes, barre de sort
      Groupe / Raid   : affichage et disposition, reglages pour les
                        soigneurs, icones de debuffs
      Boss / Arene    : affichage, apparence et textes (les cinq cadres)
    Tous les sous-panneaux sont construits a l ouverture (la recherche des
    options les trouve) ; seul celui du cadre choisi est montre. Un resultat
    de recherche dans un autre cadre le choisit (champ cuiReveal, Core.lua).
    Apercu des cadres tant que la page est ouverte (ns.PreviewPanel).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local FRAMES = {
    { key = "common", label = "UF_ALL" },
    { key = "player", label = "FRAMES_PLAYER" },
    { key = "target", label = "FRAMES_TARGET" },
    { key = "targettarget", label = "FRAMES_TOT" },
    { key = "focus", label = "FRAMES_FOCUS" },
    { key = "pet", label = "FRAMES_PET" },
    { key = "party", label = "UF_PARTY" },
    { key = "raid", label = "UF_RAID" },
    { key = "boss", label = "FRAMES_BOSS" },
    { key = "arena", label = "FRAMES_ARENA" },
}
local LABEL = {}
for _, f in ipairs(FRAMES) do LABEL[f.key] = f.label end

-- sections de chaque cadre, dans l ordre
local function sections(key)
    local O = ns.FramesOpt or {}
    local list = {}
    local function add(fn, ...)
        if type(fn) == "function" then
            local args = { ... }
            table.insert(list, function(p, y) return fn(p, y, unpack(args)) end)
        end
    end
    if key == "common" then
        add(O.Common)
        add(O.CastCommon)
        add(O.AuraLists)
    elseif key == "party" or key == "raid" then
        add(O.Group, key)
        add(O.Healers)
        add(O.GroupAuraFilter)
    else
        add(O.Show, key)
        add(O.Style, key)
        if key == "player" or key == "target" or key == "focus" then add(O.Cast, key) end
        if key == "player" then
            add(O.PlayerAuras)
            add(ns.BuildResourceOptions)
            add(O.Center)
            add(O.Totems)
            add(O.Swing)
        elseif key == "target" then
            add(O.TargetAuras)
        end
    end
    return list
end

local WIN_W = 440
local TOP_Y = -66          -- sous la liste deroulante et l aide
local db
local win, picker
local subs = {}

local function select(key)
    if not subs[key] then key = "common" end
    if db then db.frameSel = key end
    for k, p in pairs(subs) do p:SetShown(k == key) end
    win:SetHeight(math.floor(-TOP_Y + subs[key]:GetHeight() + 10))
    if picker and picker.Refresh then picker:Refresh() end
end

local function buildSub(key)
    local p = CreateFrame("Frame", nil, win)
    p:SetPoint("TOPLEFT", win, "TOPLEFT", 0, TOP_Y)
    p:SetSize(WIN_W, 10)
    p:Hide()
    -- un resultat de recherche dans ce sous-panneau le choisit (Core.lua)
    p.cuiReveal = function() select(key) end
    p.cuiLabel = L[LABEL[key]]
    local y = 0
    for _, fn in ipairs(sections(key)) do
        local ok, ny = pcall(fn, p, y)
        if ok and type(ny) == "number" then
            y = ny - 8
        elseif not ok then
            geterrorhandler()(ny)
        end
    end
    p:SetHeight(math.max(10, math.floor(-y + 6)))
    subs[key] = p
end

local function buildWindow()
    win = ns.UI.Window("CorpUIUnitFramesOptions", ns.TITLE .. " - " .. L.MOD_FRAMES, nil, WIN_W, 600)
    local label = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -40)
    label:SetText(L.UF_FRAME)
    picker = ns.UI.Select(win, 230, function()
        local list = {}
        for _, f in ipairs(FRAMES) do table.insert(list, { value = f.key, text = L[f.label] }) end
        return list
    end, function() return db and db.frameSel or "player" end, function(v) select(v) end)
    picker:SetPoint("LEFT", label, "RIGHT", 10, 0)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -60)
    hint:SetWidth(WIN_W - 16)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.CF_PREVIEW_HINT)
    -- apercu des cadres tant que la page est ouverte
    ns.PreviewPanel(win)
    for _, f in ipairs(FRAMES) do buildSub(f.key) end
    select(db and db.frameSel or "player")
end

-- ouvrir l editeur sur un cadre ("player", "raid"...)
function ns.OpenFrames(key)
    if not db then return end
    if not win then buildWindow() end
    if key and subs[key] then select(key) end
    ns.ShowPanel(win)
end

local function open()
    ns.OpenFrames()
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function()
    local root = ns.InitRoot()
    root.frames = root.frames or {}
    db = root.frames
    if db.frameSel == nil then db.frameSel = "player" end
end)
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")

ns.RegisterModule({
    command = "cadres",
    panelName = "CorpUIUnitFramesOptions",
    icon = "Interface\\Icons\\Achievement_Character_Human_Male",
    title = function() return L.MOD_FRAMES end,
    desc = function() return L.FRAMES_DESC end,
    Slash = function(input)
        local arg = strlower(strtrim(input or ""))
        if arg == "diag" then
            if ns.FramesDiag then ns.FramesDiag() end
            return
        end
        -- /corp cadres raid, /corp cadres cible...
        local alias = { joueur = "player", cible = "target", focalisation = "focus", familier = "pet",
                        groupe = "party", tous = "common" }
        local key = alias[arg] or (arg ~= "" and arg) or nil
        ns.OpenFrames(key)
    end,
    Open = open,
})
