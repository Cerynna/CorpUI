--[[--------------------------------------------------------------------------
    CorpUI - fonctions partagees par les modules (noyau)
    Sorts (nom, icone, connu), classes (nom, couleur, icone), temps,
    raccourcis abreges. Venues de Buffs et de Barres : d autres modules
    s en servent, elles doivent marcher meme module coupe.
----------------------------------------------------------------------------]]

local _, ns = ...
local issecret = issecretvalue or function() return false end

-- Valeur lisible (ni nil ni secrete), sinon nil
local function clean(v)
    if v == nil or issecret(v) then return nil end
    return v
end
ns.Clean = clean

function ns.SpellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and name then return name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        if ok then return name end
    end
end

function ns.SpellIcon(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and tex then return tex end
    end
    if GetSpellTexture then
        local ok, tex = pcall(GetSpellTexture, id)
        if ok then return tex end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Sort connu du joueur ? Renvoie aussi l ID du plus haut rang connu.
-- Resoudre par le nom ne marche que pour un sort appris : c est le test.
local function knownSpell(id)
    local name = ns.SpellName(id)
    if not name then return false end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and info and info.spellID then return true, info.spellID end
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, id)
        if ok and known then return true, id end
    end
    return false
end
ns.KnownSpell = knownSpell

function ns.ClassName(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and names[class]) or class
end

function ns.ClassColor(class)
    local colors = RAID_CLASS_COLORS
    local c = colors and colors[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

function ns.ClassHex(class)
    local r, g, b = ns.ClassColor(class)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

function ns.SetClassIcon(tex, class)
    tex:SetTexCoord(0, 1, 0, 1)
    local atlas = "classicon-" .. strlower(class)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
        return
    end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    if coords then tex:SetTexCoord(unpack(coords)) end
end

function ns.FormatTime(sec)
    if not sec then return "" end
    if sec >= 3600 then
        return string.format("%dh%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60))
    end
    if sec >= 60 then
        return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
    end
    return string.format("%ds", math.floor(sec))
end

-- raccourci abrege pour les boutons ("S1", "C2", "MwH"...)
local function shortKey(key)
    if not key then return "" end
    -- modificateurs en capitales ("S1", "C2", "A3")
    key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A")
    key = key:gsub("MOUSEWHEELUP", "MwH"):gsub("MOUSEWHEELDOWN", "MwB"):gsub("BUTTON", "M")
    key = key:gsub("NUMPAD", "N"):gsub("SPACE", "Esp")
    return key
end

ns.ShortKey = shortKey
