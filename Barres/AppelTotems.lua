--[[--------------------------------------------------------------------------
    CorpUI - barre des totems du chaman (remplace la barre d appel de
    Blizzard, MultiCastActionBarFrame, cachee comme les autres barres)
    Une barre du module Barres (ns.AddButtonBarPlugin) : memes reglages
    (taille, espacement, boutons par ligne, fond, opacite, survol,
    visibilite, raccourcis), deplacee avec les autres.
      - une case par element (Terre, Feu, Eau, Air, l ordre du jeu) : bouton
        d action securise sur l emplacement du jeu que la barre de Blizzard
        utilise : (barre d appel - 1) x 12 + (page - 1) x 4 + element ;
        seulement les elements que le jeu propose (comme Blizzard : totem
        de l element et sorts de totem connus) ;
      - au-dessus de chaque case (ou a cote, selon la place de la barre),
        une fleche toujours visible : la liste des totems de l element,
        puis "aucun totem". Choisir = action securisee du jeu "multispell"
        (SetMultiCastSpell), donc aussi en combat ;
      - l appel des totems (elements, ancetres, esprits : une page chacun)
        et le rappel, s ils sont connus ; la fleche de l appel choisit la
        page (deux appels connus ou plus).
    Ouverture de la liste et changement de page : extraits securises
    (WrapScript du cadre de la barre), utilisables en combat. Les listes de
    sorts sont recopiees en attributs hors combat (elles ne changent qu en
    apprenant un totem). Liste fermee apres un choix, ou une seconde apres
    que la souris l a quittee (RegisterAutoHide).
    Deverrouillage (poignees) : apercu complet, les quatre elements, l appel
    et le rappel meme pas encore appris, pour placer la barre a sa taille
    finale.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local FIRE, EARTH, WATER, AIR = FIRE_TOTEM_SLOT or 1, EARTH_TOTEM_SLOT or 2, WATER_TOTEM_SLOT or 3, AIR_TOTEM_SLOT or 4
-- ordre d affichage du jeu (SHAMAN_TOTEM_PRIORITIES) : Terre, Feu, Eau, Air
local ORDER = { EARTH, FIRE, WATER, AIR }
local ELEMENT = {
    [EARTH] = { 0.66, 0.47, 0.26 },
    [FIRE] = { 1.00, 0.45, 0.15 },
    [WATER] = { 0.25, 0.60, 1.00 },
    [AIR] = { 0.72, 0.78, 1.00 },
}
local ELEMENT_NAME = { [EARTH] = "BARS_TOTEM_EARTH", [FIRE] = "BARS_TOTEM_FIRE", [WATER] = "BARS_TOTEM_WATER", [AIR] = "BARS_TOTEM_AIR" }
-- appels (une page chacun) et rappel : Constants.lua du jeu
local SUMMON = { 66842, 66843, 66844 }
local RECALL = 36936
local MAXFLY = 13          -- 12 totems + "aucun"
local CHEV = 10            -- epaisseur de la fleche
local FLY_PAD = 3

local h, fly
local elem = {}            -- element -> bouton
local chev = {}            -- element -> fleche ; chev.page : fleche de l appel
local flyB = {}
local summonB, recallB
local shown = {}           -- boutons affiches, dans l ordre
local scan = { avail = {}, spells = {}, summon = {}, recall = false }
local lastSig

local function isShaman()
    local ok, _, class = pcall(UnitClass, "player")
    return ok and class == "SHAMAN"
end

local function knows(id)
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local ok, v = pcall(C_SpellBook.IsSpellInSpellBook, id, bank, false)
        if ok and not issecret(v) then return v and true or false end
    end
    if IsPlayerSpell then
        local ok, v = pcall(IsPlayerSpell, id)
        if ok and not issecret(v) then return v and true or false end
    end
    return false
end

local function pack(ok, ...) return ok, select("#", ...), { ... } end

-- sorts de totem d un element (dans l ordre du jeu)
local function totemSpells(slot)
    local list = {}
    local ok, n, res = pack(pcall(GetMultiCastTotemSpells, slot))
    if not ok then return list end
    for i = 1, n do
        local id = res[i]
        if type(id) == "number" and not issecret(id) and #list < MAXFLY - 1 then table.insert(list, id) end
    end
    return list
end

-- element propose par le jeu : son totem (GetTotemInfo) et des sorts
local function hasElement(slot)
    local ok, have = pcall(GetTotemInfo, slot)
    if not ok or not (issecret(have) or have) then return false end
    return #scan.spells[slot] > 0
end

-- releve de ce que le jeu propose ; renvoie une signature (changement ?)
local function doScan()
    local sig = {}
    scan.avail, scan.summon = {}, {}
    if isShaman() then
        for _, slot in ipairs(ORDER) do
            scan.spells[slot] = totemSpells(slot)
            if hasElement(slot) then
                table.insert(scan.avail, slot)
                table.insert(sig, slot .. ":" .. table.concat(scan.spells[slot], ","))
            end
        end
        for page, id in ipairs(SUMMON) do
            if knows(id) then
                table.insert(scan.summon, page)
                table.insert(sig, "s" .. page)
            end
        end
        scan.recall = knows(RECALL)
        if scan.recall then table.insert(sig, "r") end
    else
        scan.recall = false
    end
    return table.concat(sig, ";")
end

local function barBase()
    local ok, idx = pcall(C_ActionBar.GetMultiCastBarIndex)
    if not ok or type(idx) ~= "number" or issecret(idx) then idx = 12 end
    return (idx - 1) * 12
end

---------------------------------------------------------------------------
-- Extraits securises (environnement du cadre de la barre : owner)
---------------------------------------------------------------------------

-- fleche : ouvre ou ferme la liste (totems d un element, ou appels)
local CHEV_PRE = [[
    local fly = owner:GetFrameRef("fly")
    local me = self:GetName()
    if fly:IsShown() and fly:GetAttribute("from") == me then
        fly:Hide()
        return false
    end
    local kind = self:GetAttribute("kind")
    local count = self:GetAttribute("count") or 0
    if count < 1 then return false end
    local total = count
    if kind == "slot" then total = count + 1 end
    local size = owner:GetAttribute("fsize") or 32
    local gap = owner:GetAttribute("fgap") or 2
    local pad = owner:GetAttribute("fpad") or 3
    local dir = owner:GetAttribute("fdir") or "UP"
    local action
    if kind == "slot" then
        action = (owner:GetAttribute("base") or 0) + ((owner:GetAttribute("page") or 1) - 1) * 4
            + (self:GetAttribute("slot") or 1)
    end
    local n = owner:GetAttribute("fmax") or 0
    for i = 1, n do
        local b = owner:GetFrameRef("fb" .. i)
        if b and i <= total then
            b:SetAttribute("kind", kind)
            if kind == "slot" then
                b:SetAttribute("type", "multispell")
                b:SetAttribute("action", action)
                b:SetAttribute("page", nil)
                if i <= count then
                    b:SetAttribute("spell", self:GetAttribute("spell" .. i))
                else
                    b:SetAttribute("spell", 0)
                end
            else
                b:SetAttribute("type", nil)
                b:SetAttribute("action", nil)
                b:SetAttribute("page", self:GetAttribute("page" .. i))
                b:SetAttribute("spell", self:GetAttribute("spell" .. i))
            end
            b:SetWidth(size)
            b:SetHeight(size)
            b:ClearAllPoints()
            local off = pad + (i - 1) * (size + gap)
            if dir == "DOWN" then
                b:SetPoint("TOP", fly, "TOP", 0, -off)
            elseif dir == "LEFT" then
                b:SetPoint("RIGHT", fly, "RIGHT", -off, 0)
            elseif dir == "RIGHT" then
                b:SetPoint("LEFT", fly, "LEFT", off, 0)
            else
                b:SetPoint("BOTTOM", fly, "BOTTOM", 0, off)
            end
            b:Show()
        elseif b then
            b:Hide()
        end
    end
    local long = total * size + (total - 1) * gap + 2 * pad
    local thick = size + 2 * pad
    fly:ClearAllPoints()
    if dir == "LEFT" or dir == "RIGHT" then
        fly:SetWidth(long)
        fly:SetHeight(thick)
    else
        fly:SetWidth(thick)
        fly:SetHeight(long)
    end
    if dir == "DOWN" then
        fly:SetPoint("TOP", self, "BOTTOM", 0, -2)
    elseif dir == "LEFT" then
        fly:SetPoint("RIGHT", self, "LEFT", -2, 0)
    elseif dir == "RIGHT" then
        fly:SetPoint("LEFT", self, "RIGHT", 2, 0)
    else
        fly:SetPoint("BOTTOM", self, "TOP", 0, 2)
    end
    fly:SetAttribute("from", me)
    fly:SetAttribute("slot", self:GetAttribute("slot"))
    fly:SetAttribute("kind", kind)
    fly:Show()
    fly:RegisterAutoHide(1)
    fly:AddToAutoHide(self)
    return false
]]

-- bouton de la liste : un appel change la page (actions des cases, sort de
-- l appel) ; un totem laisse partir l action "multispell", puis ferme
local FB_PRE = [[
    if self:GetAttribute("kind") == "page" then
        local page = self:GetAttribute("page")
        if page then
            owner:SetAttribute("page", page)
            local base = owner:GetAttribute("base") or 0
            for s = 1, 4 do
                local e = owner:GetFrameRef("elem" .. s)
                if e then e:SetAttribute("action", base + (page - 1) * 4 + s) end
            end
            local sm = owner:GetFrameRef("summon")
            if sm then sm:SetAttribute("spell", self:GetAttribute("spell")) end
        end
        owner:GetFrameRef("fly"):Hide()
        return false
    end
    return nil, "close"
]]
local FB_POST = [[
    owner:GetFrameRef("fly"):Hide()
]]

---------------------------------------------------------------------------
-- Apparence
---------------------------------------------------------------------------

local function colorOf(slot)
    return ELEMENT[slot] or C.violet
end

local function elementName(slot)
    return L[ELEMENT_NAME[slot]] or tostring(slot)
end

-- liste : liseré de l element (violet : appels), le choix actuel en or
local function dressFly()
    if not fly then return end
    local kind = fly:GetAttribute("kind")
    local c = kind == "slot" and colorOf(fly:GetAttribute("slot")) or C.violet
    fly.cuiBorder:SetColorTexture(c[1], c[2], c[3], 1)
    local page = h and h:GetAttribute("page")
    for _, fb in ipairs(flyB) do
        local spell = fb:GetAttribute("spell")
        local current = false
        if kind == "slot" then
            local okI, t, id = pcall(GetActionInfo, fb:GetAttribute("action") or 0)
            if okI and not issecret(t) and not issecret(id) then
                current = (spell == 0 and t == nil) or (t == "spell" and id == spell)
            end
        else
            current = fb:GetAttribute("page") == page
        end
        local e = current and C.gold or c
        fb.cuiBorder:SetColorTexture(e[1], e[2], e[3], current and 1 or 0.7)
    end
end

local function dressFlyButton(fb)
    local spell = fb:GetAttribute("spell")
    local none = spell == 0
    fb.cross1:SetShown(none)
    fb.cross2:SetShown(none)
    if none or not spell then
        fb.icon:Hide()
        return
    end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spell)
    fb.icon:SetTexture(ok and tex or nil)
    fb.icon:Show()
end

-- cases : liseré de l element, fond teinte (visible si aucun totem choisi)
local function dressElement(b, slot)
    local c = colorOf(slot)
    b.cuiBorder:SetColorTexture(c[1], c[2], c[3], 1)
    b.empty:SetColorTexture(c[1], c[2], c[3], 0.22)
end

-- appel et rappel : icone, recharge, utilisable (Barres : update)
local function updateSpell(b)
    local id = b:GetAttribute("spell")
    if not id then
        b.icon:Hide()
        b.cd:Clear()
        return
    end
    local okT, tex = pcall(C_Spell.GetSpellTexture, id)
    b.icon:SetTexture(okT and tex or nil)
    b.icon:Show()
    -- apercu du deverrouillage : sort pas encore appris, en gris
    b.icon:SetDesaturated(b.preview and true or false)
    local done = false
    if C_Spell.GetSpellCooldownDuration and b.cd.SetCooldownFromDurationObject then
        local ok, d = pcall(C_Spell.GetSpellCooldownDuration, id)
        done = ok and d and pcall(b.cd.SetCooldownFromDurationObject, b.cd, d) or false
    end
    if not done and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" then
            if not pcall(b.cd.SetCooldown, b.cd, info.startTime, info.duration) then b.cd:Clear() end
        end
    end
    if C_Spell.IsSpellUsable then
        local okU, usable, noMana = pcall(C_Spell.IsSpellUsable, id)
        if okU and not issecret(usable) and not issecret(noMana) then
            if usable then b.icon:SetVertexColor(1, 1, 1)
            elseif noMana then b.icon:SetVertexColor(0.4, 0.4, 1)
            else b.icon:SetVertexColor(0.4, 0.4, 0.4) end
        end
    end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function spellName(id, fallback)
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and type(n) == "string" and not issecret(n) then return n end
    return fallback
end

local function bindable(b, label)
    b.bindCommand = "CLICK " .. b:GetName() .. ":LeftButton"
    b.header = h
    b.bindLabel = L.BARS_TOTEM .. " - " .. label
    if ns.RegisterBindable then ns.RegisterBindable(b, b.bindCommand) end
end

local function makeChevron(owner, name, kind, slot)
    local c = CreateFrame("Button", name, owner, "SecureActionButtonTemplate")
    c:RegisterForClicks("AnyUp")
    c:SetAttribute("useOnKeyDown", false)
    c:SetAttribute("kind", kind)
    c:SetAttribute("slot", slot)
    local border = ns.UI.Skin(c, 0.85)
    local col = colorOf(slot)
    border:SetColorTexture(col[1], col[2], col[3], 0.8)
    c.glyph = ns.UI.Chevron(c, CHEV, "UP")
    c.glyph:SetPoint("CENTER")
    c.glyph:SetVertexColor(col[1], col[2], col[3], 1)
    c.col = col
    c:SetScript("OnEnter", function(self)
        self.glyph:SetVertexColor(1, 1, 1, 1)
        local t = ns.Tooltip(self, "ANCHOR_TOPRIGHT")
        if kind == "slot" then
            t:AddLine(elementName(slot), col[1], col[2], col[3])
            t:AddLine(L.BARS_TOTEM_PICK, 1, 1, 1)
        else
            t:AddLine(L.BARS_TOTEM_PAGE, 1, 1, 1)
        end
        t:Show()
    end)
    c:SetScript("OnLeave", function(self)
        self.glyph:SetVertexColor(self.col[1], self.col[2], self.col[3], 1)
        ns.HideTooltip()
    end)
    h:WrapScript(c, "OnClick", CHEV_PRE)
    return c
end

local function makeElement(kit, idx, slot)
    local b = CreateFrame("Button", "CorpUIBartotemButton" .. idx, h, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "action")
    b:SetAttribute("action", barBase() + slot)
    b:SetAttribute("index", idx)
    b.totemSlot = slot
    bindable(b, elementName(slot))
    kit.makeVisuals(b)
    b.empty = b:CreateTexture(nil, "ARTWORK", nil, -2)
    b.empty:SetAllPoints()
    dressElement(b, slot)
    -- la page change dans le code securise : on suit l attribut
    b:HookScript("OnAttributeChanged", function(self, attr)
        if attr == "action" then kit.update(self) end
    end)
    b:SetScript("OnEnter", function(self)
        if ns.QuickBindHover and ns.QuickBindHover(self) then return end
        local t = ns.Tooltip(self, "ANCHOR_TOPRIGHT")
        local action = self:GetAttribute("action")
        local okH, has = pcall(HasAction, action)
        if okH and has and pcall(t.SetAction, t, action) then
            t:Show()
            return
        end
        local col = colorOf(slot)
        t:AddLine(elementName(slot), col[1], col[2], col[3])
        t:AddLine(L.BARS_TOTEM_EMPTY, 1, 1, 1, true)
        t:Show()
    end)
    b:SetScript("OnLeave", ns.HideTooltip)
    kit.addButton(b)
    chev[slot] = makeChevron(b, "CorpUITotemChevron" .. idx, "slot", slot)
    h:SetFrameRef("elem" .. slot, b)
    elem[slot] = b
    return b
end

local function makeSpellButton(kit, name, label)
    local b = CreateFrame("Button", name, h, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "spell")
    bindable(b, label)
    kit.makeVisuals(b)
    b.cuiBorder:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], 1)
    b.customUpdate = updateSpell
    b:HookScript("OnAttributeChanged", function(self, attr)
        if attr == "spell" then kit.update(self) end
    end)
    b:SetScript("OnEnter", function(self)
        if ns.QuickBindHover and ns.QuickBindHover(self) then return end
        local t = ns.Tooltip(self, "ANCHOR_TOPRIGHT")
        if not pcall(t.SetSpellByID, t, self:GetAttribute("spell")) then t:Hide() return end
        t:Show()
    end)
    b:SetScript("OnLeave", ns.HideTooltip)
    kit.addButton(b)
    return b
end

local function makeFlyButton(i)
    local fb = CreateFrame("Button", "CorpUITotemFlyoutButton" .. i, fly, "SecureActionButtonTemplate")
    fb:RegisterForClicks("AnyUp")
    fb:SetAttribute("useOnKeyDown", false)
    fb:SetSize(32, 32)
    fb:Hide()
    ns.UI.Skin(fb, 0.9)
    fb.icon = fb:CreateTexture(nil, "ARTWORK")
    fb.icon:SetAllPoints()
    fb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- "aucun totem" : croix rouge
    fb.cross1 = fb:CreateTexture(nil, "ARTWORK", nil, 1)
    fb.cross2 = fb:CreateTexture(nil, "ARTWORK", nil, 1)
    for k, t in ipairs({ fb.cross1, fb.cross2 }) do
        t:SetColorTexture(0.9, 0.25, 0.25, 0.95)
        t:SetPoint("CENTER")
        t:SetSize(22, 2)
        pcall(t.SetRotation, t, math.rad(k == 1 and 45 or -45))
        t:Hide()
    end
    local hl = fb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)
    fb:HookScript("OnAttributeChanged", function(self, attr)
        if attr == "spell" then dressFlyButton(self) end
    end)
    fb:HookScript("OnSizeChanged", function(self, w)
        if type(w) == "number" and w > 0 then
            self.cross1:SetSize(w * 0.7, 2)
            self.cross2:SetSize(w * 0.7, 2)
        end
    end)
    fb:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_RIGHT")
        local spell = self:GetAttribute("spell")
        if spell == 0 then
            t:AddLine(L.BARS_TOTEM_NONE, 1, 1, 1)
        elseif not spell or not pcall(t.SetSpellByID, t, spell) then
            t:Hide()
            return
        end
        t:Show()
    end)
    fb:SetScript("OnLeave", ns.HideTooltip)
    h:WrapScript(fb, "OnClick", FB_PRE, FB_POST)
    h:SetFrameRef("fb" .. i, fb)
    flyB[i] = fb
end

local function build(kit)
    h = CreateFrame("Frame", "CorpUIBartotem", UIParent, "SecureHandlerStateTemplate")
    h:SetSize(1, 1)
    h.backBorder, h.back = ns.UI.Skin(h, 0.75, false)
    h.buttons = {}
    h:SetAttribute("fmax", MAXFLY)
    h:SetAttribute("fpad", FLY_PAD)
    -- page choisie (en combat aussi) : gardee pour la prochaine connexion
    h:HookScript("OnAttributeChanged", function(_, attr, value)
        if attr == "page" and type(value) == "number" then
            local d = kit.db()
            if d then d.totemPage = value end
        end
    end)
    -- liste : au-dessus des barres, a l echelle de la barre
    fly = CreateFrame("Frame", "CorpUITotemFlyout", UIParent, "SecureHandlerBaseTemplate")
    fly:SetFrameStrata("DIALOG")
    fly:SetSize(40, 40)
    fly:EnableMouse(true)
    fly:Hide()
    ns.UI.Skin(fly, 0.92, true)
    fly:HookScript("OnAttributeChanged", function(_, attr)
        if attr == "kind" or attr == "slot" or attr == "from" then dressFly() end
    end)
    fly:HookScript("OnShow", dressFly)
    h:SetFrameRef("fly", fly)
    for i = 1, MAXFLY do makeFlyButton(i) end

    summonB = makeSpellButton(kit, "CorpUIBartotemSummon", spellName(SUMMON[1], "1"))
    chev.page = makeChevron(summonB, "CorpUITotemChevronPage", "page", nil)
    h:SetFrameRef("summon", summonB)
    for idx, slot in ipairs(ORDER) do makeElement(kit, idx, slot) end
    recallB = makeSpellButton(kit, "CorpUIBartotemRecall", spellName(RECALL, "2"))
    recallB:SetAttribute("spell", RECALL)
    table.insert(h.buttons, summonB)
    for _, slot in ipairs(ORDER) do table.insert(h.buttons, elem[slot]) end
    table.insert(h.buttons, recallB)
    return h
end

---------------------------------------------------------------------------
-- Disposition (hors combat)
---------------------------------------------------------------------------

-- sens d ouverture : vers le centre de l ecran ; de cote pour une colonne
local function direction(cols, n)
    local x, y = h:GetCenter()
    local s = h:GetEffectiveScale()
    local W = UIParent:GetWidth() * UIParent:GetEffectiveScale()
    local H = UIParent:GetHeight() * UIParent:GetEffectiveScale()
    if cols == 1 and n > 1 then
        if x and x * s > W / 2 then return "LEFT" end
        return "RIGHT"
    end
    if y and y * s > H / 2 then return "DOWN" end
    return "UP"
end

local function placeChevron(c, b, dir)
    c:ClearAllPoints()
    if dir == "DOWN" then
        c:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
        c:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -2)
        c:SetHeight(CHEV)
    elseif dir == "LEFT" then
        c:SetPoint("TOPRIGHT", b, "TOPLEFT", -2, 0)
        c:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", -2, 0)
        c:SetWidth(CHEV)
    elseif dir == "RIGHT" then
        c:SetPoint("TOPLEFT", b, "TOPRIGHT", 2, 0)
        c:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", 2, 0)
        c:SetWidth(CHEV)
    else
        c:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 2)
        c:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, 2)
        c:SetHeight(CHEV)
    end
    c.glyph:SetDir(dir)
end

-- fond de la barre : etendu aux fleches si la marge ne les contient pas
local function extendBack(c, dir)
    if not h.back then return end
    local e = c.backdrop and math.max(0, CHEV + 2 - (c.padding or 0)) or 0
    local l, r, t, b = 0, 0, 0, 0
    if dir == "UP" then t = e elseif dir == "DOWN" then b = e elseif dir == "LEFT" then l = e else r = e end
    h.back:ClearAllPoints()
    h.back:SetPoint("TOPLEFT", h, "TOPLEFT", -l, t)
    h.back:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", r, -b)
    h.backBorder:ClearAllPoints()
    h.backBorder:SetPoint("TOPLEFT", h, "TOPLEFT", -l - 1, t + 1)
    h.backBorder:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", r + 1, -b - 1)
end

local function layout(hh, c, kit)
    lastSig = doScan()
    local base = barBase()
    -- page : celle d avant si son appel est connu, sinon le premier connu
    local d = kit.db()
    local page = d and d.totemPage or 1
    local ok = false
    for _, p in ipairs(scan.summon) do if p == page then ok = true end end
    if not ok then page = scan.summon[1] or 1 end
    hh:SetAttribute("base", base)
    hh:SetAttribute("page", page)
    for slot, b in pairs(elem) do b:SetAttribute("action", base + (page - 1) * 4 + slot) end
    pcall(fly.Hide, fly)

    -- deverrouillage (poignees) : apercu complet, les quatre elements,
    -- l appel et le rappel meme pas encore appris (la barre se place a sa
    -- taille finale) ; retour a la normale au reverrouillage
    local preview = ns.moversShown and true or false
    shown = {}
    if #scan.summon > 0 or preview then
        summonB:SetAttribute("spell", SUMMON[page])
        summonB.preview = #scan.summon == 0
        table.insert(shown, summonB)
    end
    local pc = chev.page
    pc:SetAttribute("count", #scan.summon)
    for i, p in ipairs(scan.summon) do
        pc:SetAttribute("page" .. i, p)
        pc:SetAttribute("spell" .. i, SUMMON[p])
    end
    local avail = {}
    for _, slot in ipairs(scan.avail) do avail[slot] = true end
    for _, slot in ipairs(ORDER) do
        local cv = chev[slot]
        local list = avail[slot] and scan.spells[slot] or {}
        cv:SetAttribute("count", #list)
        for i, id in ipairs(list) do cv:SetAttribute("spell" .. i, id) end
        if avail[slot] or preview then table.insert(shown, elem[slot]) end
    end
    if scan.recall or preview then
        recallB.preview = not scan.recall
        table.insert(shown, recallB)
    end
    for _, b in ipairs(h.buttons) do
        local on = false
        for _, s in ipairs(shown) do if s == b then on = true end end
        b:SetShown(on)
    end

    ns.LayoutButtonBar(hh, shown, #shown, c, kit.pos("totem"))
    local per = math.max(1, math.min(c.perRow, math.max(1, #shown)))
    local dir = direction(per, #shown)
    hh:SetAttribute("fdir", dir)
    hh:SetAttribute("fsize", c.size)
    hh:SetAttribute("fgap", math.max(2, c.spacing))
    fly:SetScale(hh:GetScale())
    for _, b in ipairs(shown) do
        kit.style(b, c)
        -- une case vide se remplit par sa fleche : jamais cachee
        b.hideEmpty = false
        b.count:Hide()
        b.macro:Hide()
        kit.update(b)
    end
    for slot, cv in pairs(chev) do
        local b = slot == "page" and summonB or elem[slot]
        local on = b:IsShown() and (slot ~= "page" or #scan.summon > 1 or preview)
        placeChevron(cv, b, dir)
        cv:SetShown(on and true or false)
    end
    extendBack(c, dir)
end

---------------------------------------------------------------------------
-- Evenements : elements appris, totems choisis
---------------------------------------------------------------------------

local kitRef
local queued = false
local function relayout()
    queued = false
    if not h or not kitRef then return end
    if doScan() ~= lastSig then kitRef.refresh(h) end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("barres", ev) then return end
    if not h or not kitRef then return end
    if event == "UPDATE_MULTI_CAST_ACTIONBAR" then
        -- totems choisis : icones des cases (permis en combat)
        for _, b in pairs(elem) do kitRef.update(b) end
        if fly:IsShown() then dressFly() end
    end
    if not queued then
        queued = true
        C_Timer.After(0.2, relayout)
    end
end)
for _, e in ipairs({ "UPDATE_MULTI_CAST_ACTIONBAR", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_ENTERING_WORLD" }) do
    pcall(ev.RegisterEvent, ev, e)
end

ns.AddButtonBarPlugin({
    key = "totem",
    name = function() return L.BARS_TOTEM end,
    hint = function() return L.BARS_TOTEM_HINT end,
    only = isShaman,
    pos = { point = "BOTTOM", x = -250, y = 284 },
    defaults = { size = 32, perRow = 6, buttons = 6 },
    build = function(kit)
        kitRef = kit
        return build(kit)
    end,
    layout = layout,
    available = function()
        if ns.moversShown then return true end
        doScan()
        return #scan.avail > 0
    end,
    count = function() return #shown end,
    blizzard = { "MultiCastActionBarFrame" },
})
