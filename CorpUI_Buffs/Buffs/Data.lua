--[[--------------------------------------------------------------------------
    CorpUI - module Buffs : donnees statiques
    Tous les sorts sont designes par leur ID de rang 1 : le nom localise est
    resolu a l execution, et lancer un sort par son nom sans rang lance
    toujours le rang le plus haut connu.

    Deux facons de buffer :
      mode "class" (paladin) : la supreme touche toute une classe
      mode "group" (pretre, mage, druide) : la priere/illumination/don
               touche tout un groupe du raid (1 a 8)
    Un buff "indivOnly" n a pas de version de groupe : il ne s assigne
    qu a des joueurs precis (Epines, Amplification...).
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)

ns.CLASSES = {
    "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN",
    "HUNTER", "MAGE", "WARLOCK", "SHAMAN",
}

-- Classes sans mana : inutile de leur donner Intelligence ou Esprit
ns.NO_MANA = { WARRIOR = true, ROGUE = true }

ns.PROVIDER_ORDER = { "PALADIN", "PRIEST", "MAGE", "DRUID" }

ns.PROVIDERS = {
    PALADIN = {
        mode = "class",
        rez = 7328,          -- Redemption
        buffs = {
            { key = "wisdom",    single = 19742, group = 25894, talent = 20244, reagents = { 21177 } },
            { key = "might",     single = 19740, group = 25782, talent = 20042, reagents = { 21177 } },
            { key = "kings",     single = 20217, group = 25898, rare = true,    reagents = { 21177 } },
            { key = "salvation", single = 1038,  group = 25895,                 reagents = { 21177 } },
            { key = "light",     single = 19977, group = 25890,                 reagents = { 21177 } },
            { key = "sanctuary", single = 20911, group = 25899, rare = true,    reagents = { 21177 } },
        },
    },
    PRIEST = {
        mode = "group",
        rez = 2006,          -- Resurrection
        buffs = {
            { key = "fortitude",  single = 1243,  group = 21562, auto = true, reagents = { 17028, 17029 } },
            { key = "spirit",     single = 14752, group = 27681, auto = true, manaOnly = true, reagents = { 17029 } },
            { key = "shadowprot", single = 976,   group = 27683, reagents = { 17029 } },
        },
    },
    MAGE = {
        mode = "group",
        buffs = {
            { key = "intellect", single = 1459, group = 23028, auto = true, manaOnly = true, reagents = { 17020 } },
            { key = "amplify",   single = 1008, indivOnly = true },
            { key = "dampen",    single = 604,  indivOnly = true },
        },
    },
    DRUID = {
        mode = "group",
        rez = 20484,         -- Renaissance (aussi en combat ; composant, longue recharge)
        buffs = {
            { key = "wild",   single = 1126, group = 21849, auto = true, reagents = { 17021, 17026 } },
            { key = "thorns", single = 467,  indivOnly = true },
        },
    },
    -- aucun buff de groupe : seulement la resurrection (pas d onglet
    -- d assignation : absent de PROVIDER_ORDER)
    SHAMAN = {
        mode = "group",
        rez = 2008,          -- Esprit ancestral
        buffs = {},
    },
}

-- Paladin : auras et Fureur vertueuse
ns.AURAS = {
    { key = "devotion",      id = 465   },
    { key = "retribution",   id = 7294  },
    { key = "concentration", id = 19746 },
    { key = "shadow",        id = 19876 },
    { key = "frost",         id = 19888 },
    { key = "fire",          id = 19891 },
    { key = "sanctity",      id = 20218 },
    { key = "crusader",      id = 32223 },  -- n existe que si le client la connait
}
ns.RIGHTEOUS_FURY = 25780

-- Priorites de l auto-assignation des paladins, par classe
ns.PRIORITY = {
    WARRIOR = { "kings", "might", "light", "salvation", "sanctuary" },
    ROGUE   = { "might", "kings", "salvation", "light", "sanctuary" },
    PRIEST  = { "wisdom", "kings", "salvation", "light", "sanctuary" },
    DRUID   = { "wisdom", "kings", "salvation", "might", "light" },
    PALADIN = { "wisdom", "kings", "salvation", "might", "light" },
    HUNTER  = { "might", "wisdom", "kings", "salvation", "light" },
    MAGE    = { "wisdom", "kings", "salvation", "light", "sanctuary" },
    WARLOCK = { "wisdom", "kings", "salvation", "light", "sanctuary" },
    SHAMAN  = { "wisdom", "kings", "salvation", "might", "light" },
}

-- Resurrections annoncees au groupe (meme lancees hors de la barre) :
-- Resurrection, Redemption, Renaissance, Esprit ancestral
ns.REZ_SPELLS = { 2006, 7328, 20484, 2008 }
ns.REZ_DURATION = 12          -- incantation de 10 s + marge

-- Ordre de resurrection : les soigneurs d abord
ns.REZ_PRIORITY = { PRIEST = 1, PALADIN = 2, SHAMAN = 3, DRUID = 4 }

-- Seuils d alerte des minuteries (secondes)
ns.WARN_GROUP  = 120
ns.WARN_SINGLE = 60

ns.MAX_GROUPS = 8

---------------------------------------------------------------------------
-- Index derives
---------------------------------------------------------------------------

ns.BUFF_BY_KEY = {}
for class, p in pairs(ns.PROVIDERS) do
    p.class = class
    for i, b in ipairs(p.buffs) do
        b.index = i
        b.provider = class
        ns.BUFF_BY_KEY[b.key] = b
    end
end

ns.AURA_BY_KEY = {}
for i, a in ipairs(ns.AURAS) do
    a.index = i
    ns.AURA_BY_KEY[a.key] = a
end

ns.CLASS_INDEX = {}
for i, c in ipairs(ns.CLASSES) do ns.CLASS_INDEX[c] = i end
