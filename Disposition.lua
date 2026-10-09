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
        barres de droite plus fines sur un fond ;
      - (phase 6) au centre la barre de puissance et les procs (Cadres        Centre.lua), le nom du joueur dans sa barre, sans mana sous le cadre
        ni pastille Zz ; cases vides des barres masquees ; coins degages :
        CD du groupe seulement en groupe, compteur cote a cote en bas a
        droite au-dessus du bandeau d infos, micro-menu sous les barres.
    Une entree peut avoir need(root) : posee (et remise) seulement si vrai
    (fenetres du compteur : on ne cree pas celles qui n existent pas).
    Les reglages remplaces sont gardes (CorpUIDB.layoutBackup, par profil,
    rangee par nom de reglage : une entree ajoutee a la liste est gardee a
    la pose suivante) : "Ma disposition d avant" les remet. Les modules
    lisent ces reglages a la connexion : il faut recharger l interface.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local Layout = {}
ns.ModernLayout = Layout

-- fenetre n du compteur (seulement si elle existe) : 214 x 170, pied a 33
-- (bandeau d infos de 23 en dessous, 6 d ecart), bord droit a x
local function meterWindow(n, x)
    local function need(root)
        return type(root.meter) == "table" and type(root.meter.windows) == "table"
            and type(root.meter.windows[n]) == "table"
    end
    return { "meter", { "windows", n }, { pos = { point = "BOTTOMRIGHT", x = x, y = 33 }, w = 214, h = 170 },
        need = need }
end

-- { module (sous-table de CorpUIDB), chemin, valeurs, replace = la table
-- entiere est remplacee (positions) ; sinon fusion cle par cle }
local CHANGES = {
    { "frames", { "playerPos" }, { point = "CENTER", x = -175, y = -170 }, replace = true },
    { "frames", { "targetPos" }, { point = "CENTER", x = 175, y = -162 }, replace = true },
    { "frames", { "totPos" }, { point = "CENTER", x = 222, y = -199 }, replace = true },
    -- (phase 6 : sans mana sous le cadre, elle est au centre ; nom a gauche)
    { "frames", { "style", "player" }, { width = 180, top = 0, hp = 22, power = 0, valueSize = 12, portrait = "none",
        texts = { nameL = "none", nameR = "none", hpL = "name", hpC = "none", hpR = "hp:curpct", pwC = "none" } } },
    { "frames", { "style", "target" }, { width = 180, top = 16, hp = 22, power = 4, nameSize = 12, valueSize = 12,
        portrait = "none",
        texts = { nameL = "name", nameR = "level", hpL = "none", hpC = "none", hpR = "hp:curpct", pwC = "none" } } },
    { "frames", { "style", "targettarget" }, { width = 86, top = 0, hp = 14, power = 0, valueSize = 10, portrait = "none",
        texts = { nameL = "none", nameR = "none", hpL = "nameshort", hpC = "none", hpR = "hp:pct", pwC = "none" } } },
    { "cast", { "conf", "player" }, { attach = true, height = 14, icon = false, textSize = 10, showTime = true } },
    { "cast", { "conf", "target" }, { attach = true, height = 12, icon = true, textSize = 10, showTime = true } },
    -- (phase 6 : un peu plus haut, la barre de puissance est dessous)
    { "auras", { "debuffPos" }, { point = "CENTER", x = 0, y = -108 }, replace = true },
    { "auras", { "layout", "debuffs" }, { size = 24, perRow = 6, max = 12, spacing = 3, grow = "down", time = "below",
        center = true } },
    { "auras", { "layout", "target" }, { size = 20, perRow = 8, max = 16, spacing = 2, grow = "up", time = "none" } },
    -- phase 2 : barres d action compactes en bas au centre, empilees
    -- au-dessus du bandeau d infos ; familier au-dessus ; barres de droite
    -- plus fines, sur un fond
    { "bars", { "bar", "main" }, { size = 34, spacing = 2, perRow = 12, backdrop = false, hideEmpty = true } },
    { "bars", { "bar", "bl" }, { size = 34, spacing = 2, perRow = 12, backdrop = false, hideEmpty = true } },
    { "bars", { "bar", "br" }, { size = 34, spacing = 2, perRow = 12, backdrop = false, hideEmpty = true } },
    { "bars", { "pos", "main" }, { point = "BOTTOM", x = 0, y = 34 }, replace = true },
    { "bars", { "pos", "bl" }, { point = "BOTTOM", x = 0, y = 70 }, replace = true },
    { "bars", { "pos", "br" }, { point = "BOTTOM", x = 0, y = 106 }, replace = true },
    { "bars", { "bar", "pet" }, { size = 26, spacing = 2 } },
    { "bars", { "pos", "pet" }, { point = "BOTTOM", x = 0, y = 144 }, replace = true },
    { "bars", { "bar", "right" }, { size = 28, spacing = 4, backdrop = false, padding = 4, bgAlpha = 55, hideEmpty = true } },
    { "bars", { "bar", "right2" }, { size = 28, spacing = 4, backdrop = false, padding = 4, bgAlpha = 55, hideEmpty = true } },
    -- au bord droit de l ecran (comme la maquette), l une a cote de l autre
    { "bars", { "pos", "right" }, { point = "RIGHT", x = -6, y = 0 }, replace = true },
    { "bars", { "pos", "right2" }, { point = "RIGHT", x = -50, y = 0 }, replace = true },
    -- phase 3 : buffs du joueur plus serres, a gauche de la minicarte
    { "auras", { "layout", "buffs" }, { size = 26, spacing = 3 } },
    -- phase 4 : chat et bandeau d infos plus transparents
    { "chat", { "alpha" }, 0.35, replace = true },
    { "info", { "alpha" }, 70, replace = true },
    -- phase 5 : plaques fines, textes dans la barre ; barre d XP fine, sans
    -- les lignes de temps, de session ni d XP par heure
    { "plates", { "textInside" }, true, replace = true },
    { "plates", { "width" }, 140, replace = true },
    { "plates", { "height" }, 14, replace = true },
    -- (reglage par reglage : la table xp garde aussi les compteurs de temps
    -- par personnage, qu un retour en arriere ne doit pas toucher)
    { "xp", { "width" }, 420, replace = true },
    { "xp", { "height" }, 14, replace = true },
    { "xp", { "textSize" }, 9, replace = true },
    { "xp", { "tLevelTime" }, false, replace = true },
    { "xp", { "tSession" }, false, replace = true },
    { "xp", { "tRate" }, false, replace = true },
    { "xp", { "tETA" }, false, replace = true },
    { "xp", { "tBottom" }, false, replace = true },
    -- phase 6 : centre facon maquette, coins degages
    { "center", { "enabled" }, true, replace = true },
    -- un peu d air entre la barre et les cadres (ils sont a +-85)
    { "center", { "width" }, 150, replace = true },
    { "frames", { "restIcon" }, false, replace = true },
    { "cd", { "raid", "vis" }, "group", replace = true },
    -- bandeau d infos en bas a droite (ips, ms, heure, or...), sous le compteur
    { "info", { "pos" }, { point = "BOTTOMRIGHT", x = -4, y = 4 }, replace = true },
    { "info", { "width" }, 436, replace = true },
    { "info", { "align" }, "spread", replace = true },
    { "info", { "fontSize" }, 12, replace = true },
    { "info", { "spacing" }, 14, replace = true },
    { "info", { "items", "fps" }, true, replace = true },
    { "info", { "items", "lat" }, true, replace = true },
    { "info", { "items", "time" }, true, replace = true },
    { "info", { "order" }, { "fps", "lat", "time", "gold", "dur", "bags", "guild", "friends", "coords" }, replace = true },
    -- compteur : les deux premieres fenetres cote a cote au-dessus du bandeau
    meterWindow(1, -226),
    meterWindow(2, -4),
    -- micro-menu : sous les barres d action, a la place de l ancien bandeau
    { "menus", { "microPos" }, { point = "BOTTOM", x = 0, y = 6 }, replace = true },
    { "menus", { "microStyle" }, { size = 22, spacing = 2 } },
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
        if not c.need or c.need(root) then
            local t, key = parentOf(root, c)
            local id = idOf(c)
            if backup[id] == nil then backup[id] = { v = deep(t[key]) } end
            if c.replace or type(t[key]) ~= "table" then
                t[key] = deep(c[3])
            else
                for k, v in pairs(c[3]) do t[key][k] = deep(v) end
            end
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
        if type(b) == "table" and (not c.need or c.need(root)) then
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
