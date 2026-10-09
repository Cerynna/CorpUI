--[[--------------------------------------------------------------------------
    CorpUI - disposition Moderne (style Moderne, phase 1)

    Un clic (onglet General) pose les reglages des maquettes sur les modules
    existants, sans code de dessin nouveau :
      - cadre joueur : 180 de large, sans portrait ni bandeau, "vie  %" a
        droite, fine barre de mana, a gauche sous le personnage ;
      - cadre cible : meme taille a droite, nom et niveau au-dessus ;
      - cible de la cible : petite barre sous la cible, a droite ;
      - barre de sort du joueur accrochee sous son cadre, fine, sans icone ;
        celle de la cible accrochee sous la cible ;
      - debuffs du joueur au centre, entre les deux cadres ; auras de la
        cible plus petites, au-dessus d elle ;
      - (phase 2) barres d action serrees en bas au centre (34 px, 2 d
        ecart, empilees au-dessus du bandeau d infos), familier au-dessus,
        barres de droite plus fines sur un fond.
    Les reglages remplaces sont gardes (CorpUIDB.layoutBackup, par profil,
    rangee par nom de reglage : une entree ajoutee a la liste est gardee a
    la pose suivante) : "Ma disposition d avant" les remet. Les modules
    lisent ces reglages a la connexion : il faut recharger l interface.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local Layout = {}
ns.ModernLayout = Layout

-- { module (sous-table de CorpUIDB), chemin, valeurs, replace = la table
-- entiere est remplacee (positions) ; sinon fusion cle par cle }
local CHANGES = {
    { "frames", { "playerPos" }, { point = "CENTER", x = -175, y = -170 }, replace = true },
    { "frames", { "targetPos" }, { point = "CENTER", x = 175, y = -162 }, replace = true },
    { "frames", { "totPos" }, { point = "CENTER", x = 222, y = -199 }, replace = true },
    { "frames", { "style", "player" }, { width = 180, top = 0, hp = 22, power = 4, valueSize = 12, portrait = "none",
        texts = { nameL = "none", nameR = "none", hpL = "none", hpC = "none", hpR = "hp:curpct", pwC = "none" } } },
    { "frames", { "style", "target" }, { width = 180, top = 16, hp = 22, power = 4, nameSize = 12, valueSize = 12,
        portrait = "none",
        texts = { nameL = "name", nameR = "level", hpL = "none", hpC = "none", hpR = "hp:curpct", pwC = "none" } } },
    { "frames", { "style", "targettarget" }, { width = 86, top = 0, hp = 14, power = 0, valueSize = 10, portrait = "none",
        texts = { nameL = "none", nameR = "none", hpL = "nameshort", hpC = "none", hpR = "hp:pct", pwC = "none" } } },
    { "cast", { "conf", "player" }, { attach = true, height = 14, icon = false, textSize = 10, showTime = true } },
    { "cast", { "conf", "target" }, { attach = true, height = 12, icon = true, textSize = 10, showTime = true } },
    { "auras", { "debuffPos" }, { point = "CENTER", x = 0, y = -126 }, replace = true },
    { "auras", { "layout", "debuffs" }, { size = 24, perRow = 6, max = 12, spacing = 3, grow = "down", time = "below" } },
    { "auras", { "layout", "target" }, { size = 20, perRow = 8, max = 16, spacing = 2, grow = "up", time = "none" } },
    -- phase 2 : barres d action compactes en bas au centre, empilees
    -- au-dessus du bandeau d infos ; familier au-dessus ; barres de droite
    -- plus fines, sur un fond
    { "bars", { "bar", "main" }, { size = 34, spacing = 2, perRow = 12, backdrop = false } },
    { "bars", { "bar", "bl" }, { size = 34, spacing = 2, perRow = 12, backdrop = false } },
    { "bars", { "bar", "br" }, { size = 34, spacing = 2, perRow = 12, backdrop = false } },
    { "bars", { "pos", "main" }, { point = "BOTTOM", x = 0, y = 34 }, replace = true },
    { "bars", { "pos", "bl" }, { point = "BOTTOM", x = 0, y = 70 }, replace = true },
    { "bars", { "pos", "br" }, { point = "BOTTOM", x = 0, y = 106 }, replace = true },
    { "bars", { "bar", "pet" }, { size = 26, spacing = 2 } },
    { "bars", { "pos", "pet" }, { point = "BOTTOM", x = 0, y = 144 }, replace = true },
    { "bars", { "bar", "right" }, { size = 28, spacing = 4, backdrop = true, padding = 4, bgAlpha = 55 } },
    { "bars", { "bar", "right2" }, { size = 28, spacing = 4, backdrop = true, padding = 4, bgAlpha = 55 } },
    -- au bord droit de l ecran (comme la maquette), l une a cote de l autre
    { "bars", { "pos", "right" }, { point = "RIGHT", x = -6, y = 0 }, replace = true },
    { "bars", { "pos", "right2" }, { point = "RIGHT", x = -50, y = 0 }, replace = true },
}
Layout.CHANGES = CHANGES

-- nom stable d un reglage touche ("frames:style.player") : la sauvegarde
-- est rangee par nom, une nouvelle entree de la liste se sauvegarde a la
-- pose suivante sans toucher aux anciennes
local function idOf(c) return c[1] .. ":" .. table.concat(c[2], ".") end
Layout.IdOf = idOf

-- sauvegarde des premieres versions : rangee par position dans la liste
-- (les 11 premieres entrees, inchangees) -> par nom
local function migrate(backup)
    if type(backup) ~= "table" or backup[1] == nil then return backup end
    local out = {}
    for i, v in ipairs(backup) do
        if CHANGES[i] then out[idOf(CHANGES[i])] = v end
    end
    return out
end

local function deep(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deep(x) end
    return t
end

-- table parente du chemin (creee au besoin) et derniere cle
local function parentOf(root, c)
    local t = root[c[1]]
    if type(t) ~= "table" then
        t = {}
        root[c[1]] = t
    end
    local path = c[2]
    for i = 1, #path - 1 do
        if type(t[path[i]]) ~= "table" then t[path[i]] = {} end
        t = t[path[i]]
    end
    return t, path[#path]
end

-- pose la disposition ; garde les reglages d avant (une seule fois par
-- reglage : reposer la disposition ne les ecrase pas)
function Layout.Apply()
    local root = ns.root
    if not root then return false end
    if InCombatLockdown() then
        ns.Say(L.COMBAT_BLOCKED)
        return false
    end
    local backup = migrate(root.layoutBackup) or {}
    for _, c in ipairs(CHANGES) do
        local t, key = parentOf(root, c)
        local id = idOf(c)
        if backup[id] == nil then backup[id] = { v = deep(t[key]) } end
        if c.replace or type(t[key]) ~= "table" then
            t[key] = deep(c[3])
        else
            for k, v in pairs(c[3]) do t[key][k] = deep(v) end
        end
    end
    root.layoutBackup = backup
    ns.Say(L.LAYOUT_DONE)
    return true
end

-- remet les reglages d avant la disposition Moderne
function Layout.Restore()
    local root = ns.root
    local backup = root and migrate(root.layoutBackup)
    if type(backup) ~= "table" then return false end
    if InCombatLockdown() then
        ns.Say(L.COMBAT_BLOCKED)
        return false
    end
    for _, c in ipairs(CHANGES) do
        local b = backup[idOf(c)]
        if type(b) == "table" then
            local t, key = parentOf(root, c)
            t[key] = deep(b.v)
        end
    end
    root.layoutBackup = nil
    ns.Say(L.LAYOUT_RESTORED)
    return true
end

function Layout.HasBackup()
    return ns.root ~= nil and type(ns.root.layoutBackup) == "table"
end
