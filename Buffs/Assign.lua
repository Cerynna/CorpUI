--[[--------------------------------------------------------------------------
    CorpUI - module Buffs : fenetre d assignation (/bf)

    Un onglet par classe qui donne des buffs.
      Paladin : une ligne par paladin, une case par classe (+ aura)
        clic gauche / molette : benediction suivante
        clic droit            : benediction precedente
        maj + clic            : vider la case
      Pretre / Mage / Druide : une ligne par lanceur et par buff de groupe,
        une case par groupe du raid (1 a 8)
        clic      : donner ou retirer ce groupe
        maj + clic: vider toute la ligne
    Rien ici n est securise : la fenetre ne lance aucun sort.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local tooltip = ns.Tooltip
local hideTip = ns.HideTooltip

local PAD      = 12
local NAME_W   = 118
local SKILL_SZ = 18
local SKILL_W  = #ns.PROVIDERS.PALADIN.buffs * SKILL_SZ + 34
local BUFF_W   = 74
local CELL     = 30
local CELL_GAP = 4
local ROW_H    = 38
local HEAD_H   = 44
local TITLE_H  = 40
local TAB_H    = 28
local FOOT_H   = 84

local WIDTH = PAD * 2 + NAME_W + SKILL_W + (CELL + CELL_GAP) * (#ns.CLASSES + 1)
local TOP_H = TITLE_H + TAB_H

local win
local tabs = {}
local palRows, grpRows = {}, {}
local palHead, grpHead
local currentTab

---------------------------------------------------------------------------
-- Briques
---------------------------------------------------------------------------

-- style commun du theme CorpUI
local setBackdrop = ns.UI.SetBackdrop
ns.SetBackdrop = setBackdrop

local C = ns.COLORS

local function makeCell(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(CELL, CELL)
    setBackdrop(b, 0.85)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.plus = b:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    b.plus:SetPoint("CENTER", 0, 1)
    b.plus:SetText("+")
    b.plus:SetAlpha(0.35)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(b.icon)
    ns.UI.Gradient(b.hl, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.1, C.violet[1], C.violet[2], C.violet[3], 0.4)
    b:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 1, 1, 1) end)
    b:HookScript("OnLeave", function(self) self:Mark(self.on) end)
    -- case remplie : liseré d or, sinon liseré du theme et "+"
    function b.Mark(self, on)
        self.on = on
        local c = on and C.gold or C.border
        self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        self.plus:SetShown(not on)
    end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:EnableMouseWheel(true)
    b:SetScript("OnLeave", hideTip)
    return b
end

local makeButton, makeCheck = ns.UI.Button, ns.UI.Check

local function noRights(caster)
    ns.Say(string.format(L.NO_RIGHTS, caster))
end

---------------------------------------------------------------------------
-- Cellule du nom, commune aux deux grilles
---------------------------------------------------------------------------

local function nameTooltip(row)
    local p = ns.casters[row.caster]
    local class = ns.CasterClass(row.caster)
    local t = tooltip(row.nameBtn)
    t:AddLine(row.caster, ns.ClassColor(class or "PRIEST"))
    if p and p.addon then
        t:AddLine("CorpUI " .. (p.version or "?"), 1, 1, 1)
        t:AddLine(string.format(L.FREE_LINE, p.freeAssign and L.YES or L.NO), 1, 1, 1)
        t:AddLine(" ")
        for _, b in ipairs(ns.PROVIDERS[class].buffs) do
            local s = p.skills[b.key]
            if s then
                local line = (ns.BuffName(b.key) or b.key) .. " " .. string.format(L.RANK, s.rank or 1)
                if (s.talent or 0) > 0 then line = line .. " |cff00ff00" .. string.format(L.TALENT, s.talent) .. "|r" end
                if b.group then
                    if s.group then
                        line = line .. " |cffffd100x" .. (s.reagents or 0) .. "|r"
                    else
                        line = line .. " |cffff6060" .. L.NO_GROUP .. "|r"
                    end
                end
                t:AddLine(line, 0.9, 0.9, 0.9)
            end
        end
    else
        t:AddLine(L.NO_ADDON_TIP1, 0.6, 0.6, 0.6)
        t:AddLine(L.NO_ADDON_TIP2, 0.6, 0.6, 0.6)
    end
    t:Show()
end

local function addNameButton(row)
    row.nameBtn = CreateFrame("Button", nil, row)
    row.nameBtn:SetSize(NAME_W, ROW_H)
    row.nameBtn:SetPoint("LEFT")
    row.name = row.nameBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 2, -6)
    row.name:SetWidth(NAME_W - 4)
    row.name:SetJustifyH("LEFT")
    row.sub = row.nameBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.nameBtn:SetScript("OnEnter", function() nameTooltip(row) end)
    row.nameBtn:SetScript("OnLeave", hideTip)
end

local function updateName(row, caster, showName)
    local info = ns.CasterInfo(caster)
    local editable = ns.CanEdit(ns.me, caster)
    row.caster = caster
    row.name:SetText(showName and caster or "")
    row.name:SetTextColor(ns.ClassColor(ns.CasterClass(caster) or "PRIEST"))
    local sub = ""
    if showName then
        if not info.addon then
            sub = L.SUB_NOADDON
        elseif editable and caster ~= ns.me then
            sub = info.freeAssign and L.SUB_FREE or L.SUB_EDITABLE
        elseif not editable then
            sub = L.SUB_READONLY
        end
    end
    row.sub:SetText(sub)
    return info, editable
end

local function newRow(list, i)
    local row = CreateFrame("Frame", nil, win)
    row:SetSize(WIDTH - PAD * 2, ROW_H)
    row:SetPoint("TOPLEFT", PAD, -(TOP_H + HEAD_H + (i - 1) * ROW_H))
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(C.violet[1], C.violet[2], C.violet[3], (i % 2 == 0) and 0.07 or 0)
    addNameButton(row)
    list[i] = row
    return row
end

---------------------------------------------------------------------------
-- Grille paladin : paladin x classe
---------------------------------------------------------------------------

local function wireInput(cell, handler)
    cell:SetScript("OnClick", function(self, button)
        handler(self, button == "RightButton" and -1 or 1, IsShiftKeyDown())
    end)
    cell:SetScript("OnMouseWheel", function(self, delta)
        handler(self, delta > 0 and -1 or 1, false)
    end)
end

local function onBlessingInput(cell, step, clear)
    local pally, class = cell.caster, cell.class
    if not ns.CanEdit(ns.me, pally) then return noRights(pally) end
    local current = ns.db.assign[pally] and ns.db.assign[pally][class]
    local nextKey = nil
    if not clear then nextKey = ns.CycleBlessing(pally, class, current, step) end
    ns.SetAssign(pally, class, nextKey)
end

local function onAuraInput(cell, step, clear)
    local pally = cell.caster
    if not ns.CanEdit(ns.me, pally) then return noRights(pally) end
    local nextKey = nil
    if not clear then nextKey = ns.CycleAura(pally, ns.db.aura[pally], step) end
    ns.SetAura(pally, nextKey)
end

local function blessingTooltip(cell)
    local t = tooltip(cell)
    local key = ns.db.assign[cell.caster] and ns.db.assign[cell.caster][cell.class]
    t:AddLine(ns.ClassHex(cell.class) .. ns.ClassName(cell.class) .. "|r - " .. cell.caster)
    if key then
        t:AddLine(ns.BuffName(key, true) or key, 1, 1, 1)
    else
        t:AddLine(L.CELL_NONE, 0.6, 0.6, 0.6)
    end
    t:AddLine(" ")
    t:AddLine(L.TIP_NEXT, 0.5, 0.8, 1)
    t:AddLine(L.TIP_PREV, 0.5, 0.8, 1)
    t:AddLine(L.TIP_CLEAR, 0.5, 0.8, 1)
    t:Show()
end

local function auraTooltip(cell)
    local t = tooltip(cell)
    local akey = ns.db.aura[cell.caster]
    t:AddLine(L.AURA .. " - " .. cell.caster)
    t:AddLine(akey and ns.AuraName(akey) or L.NO_AURA, 1, 1, 1)
    t:AddLine(" ")
    t:AddLine(L.TIP_AURA_CYCLE, 0.5, 0.8, 1)
    t:Show()
end

local function createPalRow(i)
    local row = newRow(palRows, i)
    row.skills = {}
    for j, b in ipairs(ns.PROVIDERS.PALADIN.buffs) do
        local s = CreateFrame("Frame", nil, row)
        s:SetSize(SKILL_SZ - 2, SKILL_SZ - 2)
        s:SetPoint("TOPLEFT", row, "TOPLEFT", NAME_W + (j - 1) * SKILL_SZ, -4)
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetAllPoints()
        s.icon:SetTexture(ns.BuffIcon(b.key))
        s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.text:SetPoint("TOP", s, "BOTTOM", 0, -1)
        s.text:SetFont(s.text:GetFont(), 9, "OUTLINE")
        row.skills[b.key] = s
    end
    row.reag = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.reag:SetPoint("LEFT", row, "LEFT", NAME_W + #ns.PROVIDERS.PALADIN.buffs * SKILL_SZ + 2, 0)

    local x = NAME_W + SKILL_W
    row.aura = makeCell(row)
    row.aura:SetPoint("LEFT", row, "LEFT", x, 0)
    wireInput(row.aura, onAuraInput)
    row.aura:SetScript("OnEnter", auraTooltip)
    x = x + CELL + CELL_GAP

    row.cells = {}
    for j, class in ipairs(ns.CLASSES) do
        local c = makeCell(row)
        c:SetPoint("LEFT", row, "LEFT", x + (j - 1) * (CELL + CELL_GAP), 0)
        c.class = class
        wireInput(c, onBlessingInput)
        c:SetScript("OnEnter", blessingTooltip)
        row.cells[class] = c
    end
    return row
end

local function updatePalRow(row, pally)
    local info, editable = updateName(row, pally, true)
    local reag
    for _, b in ipairs(ns.PROVIDERS.PALADIN.buffs) do
        local s = row.skills[b.key]
        local sk = info.skills[b.key]
        if sk then
            reag = reag or sk.reagents
            s.icon:SetDesaturated(false)
            s.icon:SetAlpha(sk.group and 1 or 0.6)
            if (sk.talent or 0) > 0 then
                s.text:SetText("|cff00ff00" .. sk.rank .. "+" .. sk.talent .. "|r")
            else
                s.text:SetText(info.addon and tostring(sk.rank or "") or "")
            end
        else
            s.icon:SetDesaturated(true)
            s.icon:SetAlpha(0.25)
            s.text:SetText("")
        end
    end
    row.reag:SetText(info.addon and ("|cffffd100x" .. (reag or 0) .. "|r") or "")

    local akey = ns.db.aura[pally]
    row.aura.caster = pally
    row.aura.icon:SetTexture(akey and ns.AuraIcon(akey) or nil)
    row.aura:Mark(akey ~= nil)
    row.aura:SetAlpha(editable and 1 or 0.7)

    local assign = ns.db.assign[pally] or {}
    for _, class in ipairs(ns.CLASSES) do
        local c = row.cells[class]
        c.caster = pally
        local key = assign[class]
        c.icon:SetTexture(key and ns.BuffIcon(key, true) or nil)
        c:Mark(key ~= nil)
        local present = ns.byClass[class] and #ns.byClass[class] > 0
        c:SetAlpha((present and 1 or 0.45) * (editable and 1 or 0.8))
        c.icon:SetDesaturated(not present)
    end
    row:Show()
end

---------------------------------------------------------------------------
-- Grille de groupes : (lanceur, buff) x groupe
---------------------------------------------------------------------------

local function onGroupClick(cell)
    local caster, key = cell.caster, cell.key
    if not ns.CanEdit(ns.me, caster) then return noRights(caster) end
    if IsShiftKeyDown() then
        ns.SetGroups(caster, key, nil)
    else
        ns.ToggleGroup(caster, key, cell.group)
    end
end

local function groupTooltip(cell)
    local t = tooltip(cell)
    t:AddLine(string.format(L.GROUP_BUFF, cell.group, ns.BuffName(cell.key, true) or cell.key) .. " - " .. cell.caster)
    for _, m in ipairs(ns.byGroup[cell.group] or {}) do
        t:AddLine(ns.ClassHex(m.class) .. m.name .. "|r")
    end
    t:AddLine(" ")
    t:AddLine(L.TIP_GROUP_TOGGLE, 0.5, 0.8, 1)
    t:AddLine(L.TIP_ROW_CLEAR, 0.5, 0.8, 1)
    t:Show()
end

local function createGrpRow(i)
    local row = newRow(grpRows, i)
    row.buffIcon = row:CreateTexture(nil, "ARTWORK")
    row.buffIcon:SetSize(22, 22)
    row.buffIcon:SetPoint("LEFT", row, "LEFT", NAME_W, 0)
    row.buffIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.buffText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.buffText:SetPoint("LEFT", row.buffIcon, "RIGHT", 4, 0)
    row.buffText:SetWidth(BUFF_W - 28)
    row.buffText:SetJustifyH("LEFT")
    row.cells = {}
    local x = NAME_W + BUFF_W
    for g = 1, ns.MAX_GROUPS do
        local c = makeCell(row)
        c:SetPoint("LEFT", row, "LEFT", x + (g - 1) * (CELL + CELL_GAP), 0)
        c.group = g
        c:SetScript("OnClick", onGroupClick)
        c:SetScript("OnEnter", groupTooltip)
        c:EnableMouseWheel(false)
        row.cells[g] = c
    end
    return row
end

local function updateGrpRow(row, caster, key, showName)
    local info, editable = updateName(row, caster, showName)
    local sk = info.skills[key] or {}
    row.buffIcon:SetTexture(ns.BuffIcon(key, true))
    row.buffIcon:SetDesaturated(not sk.group and info.addon)
    local txt = ns.BuffShort(key)
    if info.addon then txt = txt .. "\n|cffffd100x" .. (sk.reagents or 0) .. "|r" end
    row.buffText:SetText(txt)
    local set = ns.db.groups[caster] and ns.db.groups[caster][key]
    for g, c in ipairs(row.cells) do
        c.caster, c.key = caster, key
        c.icon:SetTexture(set and set[g] and ns.BuffIcon(key, true) or nil)
        c:Mark(set and set[g] and true or false)
        local present = ns.byGroup[g] and #ns.byGroup[g] > 0
        c:SetAlpha((present and 1 or 0.45) * (editable and 1 or 0.8))
        c.icon:SetDesaturated(not present)
    end
    row:Show()
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

-- bandeau sombre derriere les en-tetes de colonnes
local function headBand(f)
    local b = f:CreateTexture(nil, "BACKGROUND")
    b:SetPoint("TOPLEFT", PAD, 0)
    b:SetPoint("BOTTOMRIGHT", -PAD, 2)
    ns.UI.Gradient(b, "VERTICAL", 0, 0, 0, 0.35, 0, 0, 0, 0.1)
end

local function createPalHead()
    palHead = CreateFrame("Frame", nil, win)
    palHead:SetPoint("TOPLEFT", 0, -TOP_H)
    palHead:SetSize(WIDTH, HEAD_H)
    headBand(palHead)
    palHead.classes = {}
    local x = PAD + NAME_W + SKILL_W
    local auraHead = palHead:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(auraHead, 10)
    auraHead:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    auraHead:SetPoint("TOP", palHead, "TOPLEFT", x + CELL / 2, -14)
    auraHead:SetText(L.AURA)
    x = x + CELL + CELL_GAP
    for j, class in ipairs(ns.CLASSES) do
        local h = CreateFrame("Frame", nil, palHead)
        h:SetSize(CELL, HEAD_H)
        h:SetPoint("TOPLEFT", palHead, "TOPLEFT", x + (j - 1) * (CELL + CELL_GAP), 0)
        h.icon = h:CreateTexture(nil, "ARTWORK")
        h.icon:SetSize(24, 24)
        h.icon:SetPoint("TOP", 0, -2)
        ns.SetClassIcon(h.icon, class)
        h.count = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        h.count:SetPoint("TOP", h.icon, "BOTTOM", 0, -2)
        h:EnableMouse(true)
        h:SetScript("OnEnter", function(self)
            local t = tooltip(self)
            t:AddLine(ns.ClassHex(class) .. ns.ClassName(class) .. "|r")
            for _, m in ipairs(ns.byClass[class] or {}) do t:AddLine(m.name, 1, 1, 1) end
            t:Show()
        end)
        h:SetScript("OnLeave", hideTip)
        palHead.classes[class] = h
    end
end

local function createGrpHead()
    grpHead = CreateFrame("Frame", nil, win)
    grpHead:SetPoint("TOPLEFT", 0, -TOP_H)
    grpHead:SetSize(WIDTH, HEAD_H)
    headBand(grpHead)
    grpHead.groups = {}
    local x = PAD + NAME_W + BUFF_W
    for g = 1, ns.MAX_GROUPS do
        local h = CreateFrame("Frame", nil, grpHead)
        h:SetSize(CELL, HEAD_H)
        h:SetPoint("TOPLEFT", grpHead, "TOPLEFT", x + (g - 1) * (CELL + CELL_GAP), 0)
        h.label = h:CreateFontString(nil, "OVERLAY")
        ns.UI.HeadFont(h.label, 12)
        h.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        h.label:SetPoint("TOP", 0, -6)
        h.label:SetText(string.format(L.GROUP_SHORT, g))
        h.count = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        h.count:SetPoint("TOP", h.label, "BOTTOM", 0, -4)
        h:EnableMouse(true)
        h:SetScript("OnEnter", function(self)
            local t = tooltip(self)
            t:AddLine(string.format(L.GROUP_LONG, g))
            for _, m in ipairs(ns.byGroup[g] or {}) do
                t:AddLine(ns.ClassHex(m.class) .. m.name .. "|r")
            end
            t:Show()
        end)
        h:SetScript("OnLeave", hideTip)
        grpHead.groups[g] = h
    end
end

local refresh

local function selectTab(class)
    currentTab = class
    ns.db.tab = class
    refresh()
end

local function createWindow()
    win = ns.NewPanel("CorpUIWindow", L.MOD_BUFFS, WIDTH, TOP_H + HEAD_H + ROW_H + FOOT_H)

    -- statut (seul / chef / membre) au bout de la rangee d onglets
    win.status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.status:SetPoint("RIGHT", win, "TOPRIGHT", -PAD, -(TITLE_H + 11))

    -- onglets : une classe qui donne des buffs par onglet
    local prev
    for _, class in ipairs(ns.PROVIDER_ORDER) do
        local t = makeButton(win, ns.ClassName(class), 90, function() selectTab(class) end)
        if prev then
            t:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            t:SetPoint("TOPLEFT", PAD, -TITLE_H)
        end
        t.class = class
        t.sel = t:CreateTexture(nil, "BACKGROUND", nil, 1)
        t.sel:SetPoint("TOPLEFT", 1, -1)
        t.sel:SetPoint("BOTTOMRIGHT", -1, 1)
        ns.UI.Gradient(t.sel, "VERTICAL", C.violet[1], C.violet[2], C.violet[3], 0.15, C.violet[1], C.violet[2], C.violet[3], 0.5)
        t.bar = t:CreateTexture(nil, "OVERLAY")
        t.bar:SetPoint("BOTTOMLEFT", 1, 1)
        t.bar:SetPoint("BOTTOMRIGHT", -1, 1)
        t.bar:SetHeight(2)
        t.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        tabs[class] = t
        prev = t
    end

    createPalHead()
    createGrpHead()

    win.sep = win:CreateTexture(nil, "ARTWORK")
    ns.UI.Gradient(win.sep, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.7, C.gold[1], C.gold[2], C.gold[3], 0)
    win.sep:SetHeight(1)
    ns.NoSnap(win.sep)
    win.sep:SetPoint("TOPLEFT", PAD, -(TOP_H + HEAD_H - 2))
    win.sep:SetPoint("TOPRIGHT", -PAD, -(TOP_H + HEAD_H - 2))

    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    win.empty:SetPoint("TOP", 0, -(TOP_H + HEAD_H + 12))

    -- pied : actions et options
    local foot = CreateFrame("Frame", nil, win)
    foot:SetPoint("BOTTOMLEFT", PAD, 8)
    foot:SetPoint("BOTTOMRIGHT", -PAD, 8)
    foot:SetHeight(FOOT_H - 10)
    local footLine = foot:CreateTexture(nil, "ARTWORK")
    footLine:SetPoint("TOPLEFT", 0, 6)
    footLine:SetPoint("TOPRIGHT", 0, 6)
    footLine:SetHeight(1)
    ns.NoSnap(footLine)
    ns.UI.Gradient(footLine, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.6, C.violet[1], C.violet[2], C.violet[3], 0)

    local bAuto = makeButton(foot, L.BTN_AUTO, 110, function() ns.AutoAssign() end)
    bAuto:SetPoint("TOPLEFT", 0, 0)
    local bClear = makeButton(foot, L.BTN_CLEAR, 80, function() ns.ClearAll() end)
    bClear:SetPoint("LEFT", bAuto, "RIGHT", 6, 0)
    local bSync = makeButton(foot, L.BTN_SYNC, 100, function()
        ns.RequestSync()
        ns.Say(L.SYNC_REQUESTED)
    end)
    bSync:SetPoint("LEFT", bClear, "RIGHT", 6, 0)
    local bReport = makeButton(foot, L.BTN_REPORT, 90, function() ns.Report() end)
    bReport:SetPoint("LEFT", bSync, "RIGHT", 6, 0)

    -- chaque case se place apres le libelle de la precedente
    win.free = makeCheck(foot, L.CHK_FREE, function(v) ns.SetFreeAssign(v) end)
    win.free:SetPoint("TOPLEFT", 0, -32)
    win.showBar = makeCheck(foot, L.CHK_SHOWBAR, function(v)
        ns.db.bar.shown = v
        ns.Changed()
    end)
    win.showBar:SetPoint("LEFT", win.free.label, "RIGHT", 16, 0)
    win.lockBar = makeCheck(foot, L.CHK_LOCK, function(v)
        ns.db.bar.locked = v
        ns.Changed()
    end)
    win.lockBar:SetPoint("LEFT", win.showBar.label, "RIGHT", 16, 0)
    win.vertical = makeCheck(foot, L.CHK_VERTICAL, function(v)
        ns.db.bar.vertical = v
        ns.Changed()
    end)
    win.vertical:SetPoint("LEFT", win.lockBar.label, "RIGHT", 16, 0)

    -- aide : sur sa propre ligne, sous les cases
    local hint = foot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 0, -58)
    hint:SetPoint("RIGHT", 0, 0)
    hint:SetJustifyH("LEFT")
    win.hint = hint
end

-- Onglet par defaut : ma classe si elle donne des buffs, sinon la premiere
-- classe presente, sinon paladin
local function defaultTab()
    if ns.db.tab and ns.PROVIDERS[ns.db.tab] then return ns.db.tab end
    if ns.MyProvider() and #ns.MyProvider().buffs > 0 then return ns.PlayerClass() end
    for _, class in ipairs(ns.PROVIDER_ORDER) do
        if #ns.CasterList(class) > 0 then return class end
    end
    return "PALADIN"
end

refresh = function()
    if not win or not win:IsShown() then return end
    currentTab = currentTab or defaultTab()
    local isPal = ns.PROVIDERS[currentTab].mode == "class"

    for class, t in pairs(tabs) do
        local n = #ns.CasterList(class)
        t:SetText(ns.ClassHex(class) .. ns.ClassName(class) .. "|r" .. (n > 0 and (" (" .. n .. ")") or ""))
        local on = class == currentTab
        t.sel:SetShown(on)
        t.bar:SetShown(on)
    end

    palHead:SetShown(isPal)
    grpHead:SetShown(not isPal)
    win.hint:SetText(isPal and L.HINT or (L.TIP_GROUP_TOGGLE .. "   " .. L.TIP_ROW_CLEAR))

    local casters = ns.CasterList(currentTab)
    local n = 0
    if isPal then
        for i, pally in ipairs(casters) do updatePalRow(palRows[i] or createPalRow(i), pally) end
        n = #casters
        for i = n + 1, #palRows do palRows[i]:Hide() end
        for _, r in ipairs(grpRows) do r:Hide() end
        for _, class in ipairs(ns.CLASSES) do
            local h = palHead.classes[class]
            local c = ns.byClass[class] and #ns.byClass[class] or 0
            h.count:SetText(c > 0 and c or "")
            h.icon:SetDesaturated(c == 0)
            h.icon:SetAlpha(c > 0 and 1 or 0.4)
        end
    else
        for _, caster in ipairs(casters) do
            local info = ns.CasterInfo(caster)
            local first = true
            for _, b in ipairs(ns.PROVIDERS[currentTab].buffs) do
                if b.group and info.skills[b.key] then
                    n = n + 1
                    updateGrpRow(grpRows[n] or createGrpRow(n), caster, b.key, first)
                    first = false
                end
            end
        end
        for i = n + 1, #grpRows do grpRows[i]:Hide() end
        for _, r in ipairs(palRows) do r:Hide() end
        for g = 1, ns.MAX_GROUPS do
            local h = grpHead.groups[g]
            local c = ns.byGroup[g] and #ns.byGroup[g] or 0
            h.count:SetText(c > 0 and c or "")
            h.label:SetAlpha(c > 0 and 1 or 0.4)
        end
    end

    win.empty:SetText(string.format(L.EMPTY_CLASS, ns.ClassName(currentTab)))
    win.empty:SetShown(n == 0)
    win:SetHeight(TOP_H + HEAD_H + math.max(n, 1) * ROW_H + FOOT_H)

    local status
    if not IsInGroup() then
        status = "|cff9a93aa" .. L.STATUS_SOLO .. "|r"
    elseif ns.IsPromoted(ns.me) then
        status = "|cff66dd77" .. L.STATUS_LEADER .. "|r"
    else
        status = "|cffffd100" .. L.STATUS_MEMBER .. "|r"
    end
    win.status:SetText(status)

    win.free:SetChecked(ns.db.freeAssign)
    win.showBar:SetChecked(ns.db.bar.shown)
    win.lockBar:SetChecked(ns.db.bar.locked)
    win.vertical:SetChecked(ns.db.bar.vertical)
end

function ns.ToggleWindow()
    if not win then createWindow() end
    ns.ShowPanel(win)
    refresh()
end

---------------------------------------------------------------------------

table.insert(ns.inits, function()
    ns.ResetPositions = function()
        if ns.ResetBar then ns.ResetBar() end
    end
end)

ns.Listen(function()
    refresh()
end, "buffs")
