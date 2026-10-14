local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)

--[[--------------------------------------------------------------------------
    CorpUI - module Recharges : sorts a temps de recharge connus

    Une entree par sort (le numero du rang 1 sert de cle, partout : partage
    entre CorpUI, reglages). Les autres rangs et la langue du client sont
    retrouves par le NOM, lu sur le client a partir de ce numero.
      id     : numero du rang 1 (cle)
      class  : classe (jeton anglais)
      cd     : recharge de base en secondes (remplacee par la vraie duree
               des qu un CorpUI la connait : talents, objets...)
      cat    : rez / raid / tank / def / kick / cc / dps / util
      lvl    : niveau d apprentissage (sorts de classe sans talent)
      talent : sort de talent (ou de race) : affiche pour un joueur sans
               CorpUI seulement apres l avoir vu lancer
      alt    : autres numeros du meme sort quand le nom differe
      item   : utilise par un objet (pas de recharge de sort a relever)
----------------------------------------------------------------------------]]

ns.CD_CATS = { "rez", "raid", "tank", "def", "kick", "cc", "dps", "util" }
-- categories cochees par defaut dans le suivi de raid
ns.CD_DEFAULT_CATS = { rez = true, raid = true, tank = true }

ns.CD_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

ns.CD_SPELLS = {
    -- Druide
    { id = 20484, class = "DRUID", cd = 1800, cat = "rez", lvl = 20 },             -- Renaissance
    { id = 29166, class = "DRUID", cd = 360, cat = "raid", lvl = 40 },             -- Innervation
    { id = 740, class = "DRUID", cd = 300, cat = "raid", lvl = 30 },               -- Tranquillite
    { id = 17116, class = "DRUID", cd = 180, cat = "raid", talent = true },        -- Rapidite de la nature
    { id = 5209, class = "DRUID", cd = 600, cat = "tank", lvl = 28 },              -- Rugissement provocateur
    { id = 22812, class = "DRUID", cd = 60, cat = "def", lvl = 44 },               -- Ecorce
    { id = 5211, class = "DRUID", cd = 60, cat = "cc", lvl = 14 },                 -- Sonner
    -- Chaman
    { id = 20608, class = "SHAMAN", cd = 3600, cat = "rez", lvl = 30, alt = { 21169 } }, -- Reincarnation
    { id = 16190, class = "SHAMAN", cd = 300, cat = "raid", talent = true },       -- Totem de vague de mana
    { id = 16188, class = "SHAMAN", cd = 180, cat = "raid", talent = true },       -- Rapidite de la nature
    { id = 8177, class = "SHAMAN", cd = 15, cat = "util", lvl = 30 },              -- Totem de glebe
    { id = 8042, class = "SHAMAN", cd = 6, cat = "kick", lvl = 4 },                -- Horion de terre
    -- Paladin
    { id = 19752, class = "PALADIN", cd = 3600, cat = "rez", lvl = 30 },           -- Intervention divine
    { id = 633, class = "PALADIN", cd = 3600, cat = "raid", lvl = 10 },            -- Imposition des mains
    { id = 1022, class = "PALADIN", cd = 300, cat = "raid", lvl = 10 },            -- Benediction de protection
    { id = 642, class = "PALADIN", cd = 300, cat = "def", lvl = 34 },              -- Bouclier divin
    { id = 498, class = "PALADIN", cd = 300, cat = "def", lvl = 6 },               -- Protection divine
    { id = 853, class = "PALADIN", cd = 60, cat = "cc", lvl = 8 },                 -- Marteau de la justice
    { id = 20066, class = "PALADIN", cd = 60, cat = "cc", talent = true },         -- Repentir
    -- Pretre
    { id = 10060, class = "PRIEST", cd = 180, cat = "raid", talent = true },       -- Infusion de puissance
    { id = 6346, class = "PRIEST", cd = 30, cat = "raid", talent = true },         -- Gardien de peur (race)
    { id = 724, class = "PRIEST", cd = 600, cat = "raid", talent = true },         -- Puits de lumiere
    { id = 14751, class = "PRIEST", cd = 180, cat = "util", talent = true },       -- Focalisation interieure
    { id = 8122, class = "PRIEST", cd = 30, cat = "cc", lvl = 14 },                -- Cri psychique
    { id = 15487, class = "PRIEST", cd = 45, cat = "kick", talent = true },        -- Silence
    { id = 586, class = "PRIEST", cd = 30, cat = "def", lvl = 8 },                 -- Oubli
    -- Guerrier
    { id = 871, class = "WARRIOR", cd = 1800, cat = "tank", lvl = 28 },            -- Mur protecteur
    { id = 12975, class = "WARRIOR", cd = 600, cat = "tank", talent = true },      -- Dernier rempart
    { id = 1161, class = "WARRIOR", cd = 600, cat = "tank", lvl = 26 },            -- Cri de defi
    { id = 355, class = "WARRIOR", cd = 10, cat = "tank", lvl = 10 },              -- Provocation
    { id = 694, class = "WARRIOR", cd = 120, cat = "tank", lvl = 16 },             -- Coup railleur
    { id = 20230, class = "WARRIOR", cd = 1800, cat = "def", lvl = 20 },           -- Represailles
    { id = 1719, class = "WARRIOR", cd = 1800, cat = "dps", lvl = 50 },            -- Temerite
    { id = 12292, class = "WARRIOR", cd = 180, cat = "dps", talent = true },       -- Souhait mortel
    { id = 5246, class = "WARRIOR", cd = 180, cat = "cc", lvl = 22 },              -- Cri d intimidation
    { id = 6552, class = "WARRIOR", cd = 10, cat = "kick", lvl = 38 },             -- Volee de coups
    { id = 72, class = "WARRIOR", cd = 12, cat = "kick", lvl = 12 },               -- Coup de bouclier
    -- Voleur
    { id = 1856, class = "ROGUE", cd = 300, cat = "def", lvl = 22 },               -- Disparition
    { id = 5277, class = "ROGUE", cd = 300, cat = "def", lvl = 8 },                -- Evasion
    { id = 1766, class = "ROGUE", cd = 10, cat = "kick", lvl = 12 },               -- Coup de pied
    { id = 2094, class = "ROGUE", cd = 300, cat = "cc", lvl = 34 },                -- Cecite
    { id = 13750, class = "ROGUE", cd = 300, cat = "dps", talent = true },         -- Poussee d adrenaline
    { id = 13877, class = "ROGUE", cd = 120, cat = "dps", talent = true },         -- Deluge de lames
    { id = 2983, class = "ROGUE", cd = 300, cat = "util", lvl = 10 },              -- Sprint
    -- Mage
    { id = 2139, class = "MAGE", cd = 30, cat = "kick", lvl = 24 },                -- Contresort
    { id = 11958, class = "MAGE", cd = 300, cat = "def", talent = true },          -- Bloc de glace
    { id = 12042, class = "MAGE", cd = 180, cat = "dps", talent = true },          -- Pouvoir des arcanes
    { id = 11129, class = "MAGE", cd = 180, cat = "dps", talent = true },          -- Combustion
    { id = 12043, class = "MAGE", cd = 180, cat = "dps", talent = true },          -- Presence spirituelle
    { id = 12051, class = "MAGE", cd = 480, cat = "util", lvl = 20 },              -- Evocation
    { id = 12472, class = "MAGE", cd = 600, cat = "util", talent = true },         -- Morsure de glace
    -- Demoniste
    { id = 20707, class = "WARLOCK", cd = 1800, cat = "rez", lvl = 18, item = true }, -- Resurrection de pierre d ame
    { id = 6789, class = "WARLOCK", cd = 120, cat = "cc", lvl = 42 },              -- Voile mortel
    { id = 5484, class = "WARLOCK", cd = 40, cat = "cc", lvl = 40 },               -- Hurlement de terreur
    -- Chasseur
    { id = 19801, class = "HUNTER", cd = 20, cat = "raid", lvl = 60 },             -- Tir tranquillisant
    { id = 5384, class = "HUNTER", cd = 30, cat = "def", lvl = 30 },               -- Feindre la mort
    { id = 19263, class = "HUNTER", cd = 300, cat = "def", talent = true },        -- Dissuasion
    { id = 3045, class = "HUNTER", cd = 300, cat = "dps", lvl = 26 },              -- Tir rapide
    { id = 19574, class = "HUNTER", cd = 120, cat = "dps", talent = true },        -- Courroux bestial
    { id = 1499, class = "HUNTER", cd = 15, cat = "cc", lvl = 20 },                -- Piege givrant
}

ns.CD_BY_ID = {}
for i, s in ipairs(ns.CD_SPELLS) do
    s.order = i
    ns.CD_BY_ID[s.id] = s
end
