--[[--------------------------------------------------------------------------
    CorpUI - fonctions partagees par les modules (noyau)
    Sorts (nom, icone, connu), classes (nom, couleur, icone), temps,
    raccourcis abreges. Venues de Buffs et de Barres : d autres modules
    s en servent, elles doivent marcher meme module coupe.
    Boite a copier l ID et le nom d un objet (double clic : sacs, banque,
    AtlasLoot).
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

---------------------------------------------------------------------------
-- Boite a copier (demande du 16/10) : l ID et le nom d un objet dans deux
-- champs, l ID deja selectionne : Ctrl+C. (Le presse-papiers du jeu,
-- CopyToClipboard, est reserve a Blizzard : un addon qui l appelle declenche
-- "action interdite".) Champs en lecture seule : une frappe remet le texte.
-- Entree, Echap ou la croix ferment.
---------------------------------------------------------------------------

local copyWin
local function copyDialog()
    if copyWin then return copyWin end
    local L, C = ns.L, ns.COLORS
    local f = CreateFrame("Frame", "CorpUIItemCopy", UIParent, "BackdropTemplate")
    f:SetSize(260, 104)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    ns.UI.SetBackdrop(f, 0.96)
    ns.UI.Shadow(f, 3)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(18, 18)
    f.icon:SetPoint("TOPLEFT", 8, -7)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- petite croix pour fermer, style de la fenetre CorpUI
    local close = CreateFrame("Button", nil, f)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -4, -5)
    local x = close:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(x, 14)
    x:SetPoint("CENTER", 0, 1)
    x:SetText("×")
    x:SetTextColor(C.text[1], C.text[2], C.text[3])
    close:SetScript("OnEnter", function() x:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function() x:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    close:SetScript("OnClick", function() f:Hide() end)
    f.close = close
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
    f.title:SetPoint("RIGHT", close, "LEFT", -4, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.fields = {}
    local function field(i, label)
        local l = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        l:SetPoint("TOPLEFT", 10, -36 - (i - 1) * 26)
        l:SetWidth(40)
        l:SetJustifyH("LEFT")
        l:SetText(label)
        local e = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        e:SetSize(196, 20)
        e:SetPoint("LEFT", l, "RIGHT", 4, 0)
        e:SetFontObject(ChatFontNormal)
        e:SetAutoFocus(false)
        e:SetTextInsets(5, 5, 0, 0)
        ns.UI.SetBackdrop(e, 0.9)
        e:SetScript("OnTextChanged", function(self, user)
            if user and self.value then
                self:SetText(self.value)
                self:HighlightText()
            end
        end)
        e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        e:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        e:SetScript("OnEnterPressed", function() f:Hide() end)
        e:SetScript("OnEscapePressed", function() f:Hide() end)
        f.fields[i] = e
        return e
    end
    field(1, L.COPY_ID)
    field(2, L.COPY_NAME)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOM", 0, 7)
    f.hint:SetText(L.COPY_HINT)
    f:SetScript("OnHide", function(self)
        for _, e in ipairs(self.fields) do e:ClearFocus() end
    end)
    function f:Open(owner, id, name, icon, r, g, b)
        local values = { tostring(id), name or "" }
        for i, e in ipairs(self.fields) do
            e.value = values[i]
            e:SetText(values[i])
            e:SetCursorPosition(0)
        end
        self.icon:SetTexture(icon)
        self.title:SetText(name or "")
        self.title:SetTextColor(r or 1, g or 1, b or 1)
        self:ClearAllPoints()
        self:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 2)
        self:Show()
        self.fields[1]:SetFocus()
        self.fields[1]:HighlightText()
    end
    f:Hide()
    copyWin = f
    return f
end

-- ouvre la boite au-dessus de owner ; nom, icone et couleur lus dans le jeu
-- s ils manquent (objet pas encore en cache : l ID seul)
function ns.UI.CopyItem(owner, id, name, icon, r, g, b)
    id = tonumber(id)
    if not (owner and id and id > 0) then return end
    if not name and C_Item and C_Item.GetItemInfo then
        local ok, n, _, quality = pcall(C_Item.GetItemInfo, id)
        if ok and type(n) == "string" and not issecret(n) then name = n end
        if ok and type(quality) == "number" and not issecret(quality) and C_Item.GetItemQualityColor then
            local ok2, cr, cg, cb = pcall(C_Item.GetItemQualityColor, quality)
            if ok2 and type(cr) == "number" then r, g, b = cr, cg, cb end
        end
    end
    if not icon then
        local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        local ok, t = pcall(get, id)
        if ok and not issecret(t) then icon = t end
    end
    copyDialog():Open(owner, id, name, icon, r, g, b)
end

---------------------------------------------------------------------------
-- AtlasLoot (addon tiers) : double clic gauche sur un objet -> meme boite.
-- Ses boutons sont des cadres d addon (AtlasLoot_Button_N, leurs boutons
-- secondaires AtlasLoot_Button_N_secButton, et AtlasLoot_SecButton_N),
-- pas de Blizzard : on ecoute leurs clics (HookScript) sans rien changer a
-- leur action (un clic gauche simple n y fait rien pour un objet ordinaire).
-- Ils portent l ID de leur objet (champ ItemID). Les nouveaux boutons sont
-- cherches une fois par seconde, seulement si AtlasLoot est charge.
---------------------------------------------------------------------------

local lastLeft = setmetatable({}, { __mode = "k" })
local function onAtlasClick(self, button)
    if button ~= "LeftButton" or IsModifierKeyDown() then return end
    local now = GetTime()
    if lastLeft[self] and now - lastLeft[self] < 0.4 then
        lastLeft[self] = nil
        local id = rawget(self, "ItemID")
        if type(id) == "number" and id > 0 then ns.UI.CopyItem(self, id) end
    else
        lastLeft[self] = now
    end
end

local hooked = setmetatable({}, { __mode = "k" })
local function hookAtlas(b)
    if type(b) ~= "table" or hooked[b] or not b.HookScript then return end
    hooked[b] = true
    pcall(b.HookScript, b, "OnClick", onAtlasClick)
end

local seen = { main = 0, sec = 0 }
local function scanAtlas()
    while true do
        local n = seen.main + 1
        local b = _G["AtlasLoot_Button_" .. n]
        if not b then break end
        seen.main = n
        hookAtlas(b)
        hookAtlas(_G["AtlasLoot_Button_" .. n .. "_secButton"])
    end
    while true do
        local n = seen.sec + 1
        local b = _G["AtlasLoot_SecButton_" .. n]
        if not b then break end
        seen.sec = n
        hookAtlas(b)
    end
end
ns.ScanAtlasLoot = scanAtlas

local function atlasLoaded()
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, "AtlasLootClassic")
    return ok and v and not issecret(v) or false
end
ns.Every(1, function()
    if atlasLoaded() then scanAtlas() end
end, "AtlasLoot : double clic")
