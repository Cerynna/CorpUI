--[[--------------------------------------------------------------------------
    CorpUI - module Guide : la fenetre du guide

    Barre du haut : guide (race et classe, ceux de la faction du
    personnage, et les quetes de donjon), avec donjons (le guide qui les
    ajoute entre 21 et 35), recaler (apres la derniere quete rendue),
    revenir a l etape en cours, remettre a zero (deux clics).
    A gauche, les parties du guide (tranche de niveaux et lieu), etapes
    faites sur le total ; l etape en cours marquee. A droite, les etapes
    de la partie choisie : case (cochee a la main en or, faite d apres le
    jeu en vert), numero, texte en couleurs et remarque.
      clic sur une etape : elle devient l etape en cours ;
      clic sur la case : la cocher ou la decocher ;
      clic sur des coordonnees : etape en cours et fleche sur ce point.
    Fenetre a nous (pas de UISpecialFrames : Echap ne la ferme pas),
    deplacable par sa barre de titre.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS
local GD = ns.Guide

local WIN_W, WIN_H = 860, 580
local LIST_W = 280
local STAGE_H = 20
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"

local win, stageScroll, stageChild, stepScroll, stepChild
local stageRows, stepRows = {}, {}
local shownPart            -- partie affichee a droite
local resetArmed

local function db() return ns.root and ns.root.guide end

local function text(parent, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    return fs
end

local function scrollArea(x, w)
    local sf = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", win, "TOPLEFT", x, -72)
    sf:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", x, 12)
    sf:SetWidth(w)
    local bg = CreateFrame("Frame", nil, win)
    bg:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4)
    bg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 22, -4)
    ns.UI.Skin(bg, 0.35)
    bg:SetFrameLevel(math.max(0, sf:GetFrameLevel() - 1))
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(w, 10)
    sf:SetScrollChild(child)
    return sf, child
end

---------------------------------------------------------------------------
-- Parties (colonne de gauche)
---------------------------------------------------------------------------

local function stageRow(i)
    if stageRows[i] then return stageRows[i] end
    local r = CreateFrame("Button", nil, stageChild)
    r:SetHeight(STAGE_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * STAGE_H)
    r:SetPoint("RIGHT", stageChild, "RIGHT", 0, 0)
    r.mark = r:CreateTexture(nil, "BACKGROUND")
    r.mark:SetAllPoints()
    ns.UI.Gradient(r.mark, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0.02)
    r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.sel:SetPoint("TOPLEFT", 0, 0)
    r.sel:SetPoint("BOTTOMLEFT", 0, 0)
    r.sel:SetWidth(2)
    r.sel:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)
    r.count = text(r, "GameFontDisableSmall")
    r.count:SetPoint("RIGHT", -4, 0)
    r.count:SetJustifyH("RIGHT")
    r.title = text(r, "GameFontHighlightSmall")
    r.title:SetPoint("LEFT", 6, 0)
    r.title:SetPoint("RIGHT", r.count, "LEFT", -4, 0)
    r.title:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
        shownPart = self.p
        GD.RefreshWindow()
        stepScroll:SetVerticalScroll(0)
    end)
    stageRows[i] = r
    return r
end

local function drawStages()
    local g, prog = GD.g, GD.prog
    local n = g and #g.e or 0
    for p = 1, n do
        local r = stageRow(p)
        local e = GD.Stage(g, p)
        r.p = p
        local done, total = GD.StageDone(g, prog, p)
        r.title:SetText(string.format("%d. %s", p, e[1]))
        r.count:SetText(string.format("%d/%d", done, total))
        local cur = p == prog.p
        r.mark:SetShown(cur)
        r.sel:SetShown(p == shownPart)
        if cur then r.title:SetTextColor(1, 1, 1)
        elseif done >= total then r.title:SetTextColor(0.5, 0.5, 0.5)
        else r.title:SetTextColor(0.85, 0.85, 0.85) end
        r:Show()
    end
    for i = n + 1, #stageRows do stageRows[i]:Hide() end
    stageChild:SetHeight(math.max(10, n * STAGE_H))
end

-- colonne de gauche sur la partie p (visible)
local function showStage(p)
    local top = (p - 1) * STAGE_H
    local h = stageScroll:GetHeight() or 0
    local cur = stageScroll:GetVerticalScroll() or 0
    if top < cur or top + STAGE_H > cur + h then
        local max = math.max(0, stageChild:GetHeight() - h)
        stageScroll:SetVerticalScroll(math.min(max, math.max(0, top - h / 3)))
    end
end

---------------------------------------------------------------------------
-- Etapes (colonne de droite)
---------------------------------------------------------------------------

local function onStepLink(self, link)
    local i = tonumber((link or ""):match("^corpguide:(%d+)$"))
    if not (i and self.p) then return end
    local prog = GD.prog
    if not (prog.p == self.p and prog.s == self.s) then GD.GoToStep(self.p, self.s) end
    GD.Aim(i)
end

local function stepRow(i)
    if stepRows[i] then return stepRows[i] end
    local r = CreateFrame("Button", nil, stepChild)
    r:RegisterForClicks("LeftButtonUp")
    pcall(r.SetHyperlinksEnabled, r, true)
    r:SetScript("OnHyperlinkClick", onStepLink)
    r.mark = r:CreateTexture(nil, "BACKGROUND")
    r.mark:SetAllPoints()
    ns.UI.Gradient(r.mark, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.3, C.violet[1], C.violet[2], C.violet[3], 0.02)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    -- case : cochee a la main (or) ou d apres le jeu (vert)
    r.box = CreateFrame("Button", nil, r)
    r.box:SetSize(14, 14)
    r.box:SetPoint("TOPLEFT", 4, -3)
    ns.UI.Skin(r.box, 0.6)
    r.box.tick = r.box:CreateTexture(nil, "OVERLAY")
    r.box.tick:SetPoint("CENTER")
    r.box.tick:SetSize(16, 16)
    r.box.tick:SetTexture(CHECK)
    r.box:SetScript("OnClick", function() if r.p then GD.ToggleStep(r.p, r.s) end end)
    r.box:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_RIGHT")
        t:AddLine(r.auto and L.GUIDE_TIP_AUTO or L.GUIDE_TIP_BOX, 1, 1, 1, true)
        t:Show()
    end)
    r.box:SetScript("OnLeave", ns.HideTooltip)
    r.num = text(r, "GameFontDisableSmall")
    r.num:SetPoint("TOPLEFT", 24, -3)
    r.num:SetWidth(24)
    r.text = text(r, "GameFontHighlight")
    r.text:SetPoint("TOPLEFT", 50, -2)
    r.text:SetWordWrap(true)
    r.note = text(r, "GameFontHighlightSmall")
    r.note:SetWordWrap(true)
    r.note:SetTextColor(0.72, 0.72, 0.72)
    r:SetScript("OnClick", function(self) if self.p then GD.GoToStep(self.p, self.s) end end)
    stepRows[i] = r
    return r
end

local function drawSteps()
    local g, prog = GD.g, GD.prog
    local p = shownPart
    local e = g and GD.Stage(g, p)
    win.partTitle:SetText(e and e[1] or "")
    win.partZone:SetText(e and (e[3] or "") or "")
    local w = stepScroll:GetWidth()
    stepChild:SetWidth(w)
    local y = 0
    local n = e and #e[4] or 0
    for s = 1, n do
        local r = stepRow(s)
        local st = GD.StepAt(g, p, s)
        r.p, r.s = p, s
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", stepChild, "TOPLEFT", 0, -y)
        r:SetWidth(w)
        local manual = prog.manual[GD.Key(p, s)] == true
        local auto = not manual and GD.AutoDone(st) == true
        local past = p < prog.p or (p == prog.p and s < prog.s)
        local cur = p == prog.p and s == prog.s
        r.auto = auto
        r.box.tick:SetShown(manual or auto)
        if manual then r.box.tick:SetVertexColor(1, 0.85, 0.3) else r.box.tick:SetVertexColor(0.4, 1, 0.4) end
        r.mark:SetShown(cur)
        r:SetAlpha((past or manual or auto) and not cur and 0.55 or 1)
        r.num:SetText(string.format("%02d)", s))
        r.text:SetWidth(w - 56)
        r.text:SetText(st.text)
        local h = math.max(14, r.text:GetStringHeight() or 0) + 4
        if st.note then
            r.note:ClearAllPoints()
            r.note:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
            r.note:SetWidth(w - 56)
            r.note:SetText(L.GUIDE_NOTE .. " " .. st.note)
            r.note:Show()
            h = h + 3 + math.max(10, r.note:GetStringHeight() or 0)
        else
            r.note:Hide()
        end
        r:SetHeight(h + 2)
        r:Show()
        y = y + h + 6
    end
    for i = n + 1, #stepRows do
        stepRows[i]:Hide()
        stepRows[i].p = nil
    end
    stepChild:SetHeight(math.max(10, y))
end

---------------------------------------------------------------------------
-- Fenetre
---------------------------------------------------------------------------

local function guideOptions()
    local list = {}
    local who = GD.who or GD.Who()
    local d = GD.Data()
    for _, g in ipairs(d and d.G or {}) do
        if not g.d and not g.ref and g.f == who.faction then
            list[#list + 1] = { value = g.k, text = GD.Label(g) }
        end
    end
    for _, g in ipairs(d and d.G or {}) do
        if g.ref and g.f == who.faction then list[#list + 1] = { value = g.k, text = GD.Label(g) } end
    end
    list.width = 220
    return list
end

local function baseKey() return GD.g and (GD.g.k:gsub("%-dungeons$", "")) or nil end

function GD.RefreshWindow()
    if not (win and win:IsShown()) then return end
    local g, prog = GD.g, GD.prog
    win.select:Refresh()
    win.dungeons:SetChecked(GD.Dungeons())
    if not g then
        win.info:SetText(GD.Data() and L.GUIDE_NONE or L.GUIDE_NO_DATA)
        drawStages()
        shownPart = nil
        drawSteps()
        return
    end
    local cur = math.min(prog.p, #g.e)
    local idx, total = GD.Index(g, cur, prog.p > #g.e and 1 or prog.s), GD.Total(g)
    if prog.p > #g.e then idx = total end
    win.info:SetText(string.format(L.GUIDE_PROGRESS, idx, total, math.floor(idx / math.max(1, total) * 100)))
    shownPart = shownPart and math.min(shownPart, #g.e) or cur
    drawStages()
    drawSteps()
end

local function build()
    local d = db()
    d.winPos = d.winPos or { point = "CENTER", x = 0, y = 20 }
    win = CreateFrame("Frame", "CorpUIGuideWindow", UIParent)
    win:SetSize(WIN_W, WIN_H)
    ns.ApplyPos(win, d.winPos)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    ns.UI.Skin(win, 0.97, true)
    win:Hide()
    local bar = CreateFrame("Frame", nil, win)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(28)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() win:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        local point, _, _, x, y = win:GetPoint(1)
        d.winPos = { point = point or "CENTER", x = x or 0, y = y or 0 }
    end)
    local title = bar:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 14)
    title:SetPoint("LEFT", 10, 0)
    title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    title:SetText(L.GUIDE_TITLE)
    win.info = text(bar, "GameFontDisableSmall")
    win.info:SetPoint("LEFT", title, "RIGHT", 12, 0)
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -4, 0)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER")
    x:SetText("×")
    close:SetScript("OnClick", function() win:Hide() end)

    -- barre d outils
    win.select = ns.UI.Select(win, 250, guideOptions, baseKey, function(v) GD.SetGuide(v) end)
    win.select:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -36)
    win.dungeons = ns.UI.Check(win, L.GUIDE_WITH_DUNGEONS, function(v) GD.SetDungeons(v) end)
    win.dungeons:SetPoint("LEFT", win.select, "RIGHT", 12, 0)
    local reset = ns.UI.Button(win, L.GUIDE_RESET, 120)
    reset:SetPoint("TOPRIGHT", win, "TOPRIGHT", -10, -36)
    reset:SetScript("OnClick", function(self)
        if resetArmed then
            resetArmed = nil
            self:SetText(L.GUIDE_RESET)
            GD.ResetProgress()
        else
            resetArmed = true
            self:SetText(L.GUIDE_RESET_SURE)
            C_Timer.After(4, function()
                if resetArmed then
                    resetArmed = nil
                    self:SetText(L.GUIDE_RESET)
                end
            end)
        end
    end)
    local current = ns.UI.Button(win, L.GUIDE_CURRENT, 120, function()
        if not GD.g then return end
        shownPart = math.min(GD.prog.p, #GD.g.e)
        GD.RefreshWindow()
        showStage(shownPart)
    end)
    current:SetPoint("RIGHT", reset, "LEFT", -6, 0)
    local catch = ns.UI.Button(win, L.GUIDE_CATCHUP, 120, function()
        GD.CatchUpNow()
        if GD.g then
            shownPart = math.min(GD.prog.p, #GD.g.e)
            GD.RefreshWindow()
            showStage(shownPart)
        end
    end)
    catch:SetPoint("RIGHT", current, "LEFT", -6, 0)
    catch:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_BOTTOM")
        t:AddLine(L.GUIDE_TIP_CATCHUP, 1, 1, 1, true)
        t:Show()
    end)
    catch:SetScript("OnLeave", ns.HideTooltip)

    stageScroll, stageChild = scrollArea(14, LIST_W)
    local rightX = 14 + LIST_W + 34
    -- titre de la partie affichee
    win.partTitle = text(win, "GameFontNormalLarge")
    win.partTitle:SetPoint("TOPLEFT", win, "TOPLEFT", rightX, -70)
    win.partZone = text(win, "GameFontDisableSmall")
    win.partZone:SetPoint("LEFT", win.partTitle, "RIGHT", 10, 0)
    stepScroll, stepChild = scrollArea(rightX, WIN_W - rightX - 36)
    stepScroll:ClearAllPoints()
    stepScroll:SetPoint("TOPLEFT", win, "TOPLEFT", rightX, -96)
    stepScroll:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", rightX, 12)
    stepScroll:SetWidth(WIN_W - rightX - 36)

    win:SetScript("OnShow", function()
        if GD.g then shownPart = math.min(GD.prog.p, #GD.g.e) end
        GD.RefreshWindow()
        if shownPart then showStage(shownPart) end
    end)
end

function GD.ToggleWindow(forceOpen)
    if not db() then return end
    if not win then build() end
    if win:IsShown() and not forceOpen then
        win:Hide()
        return
    end
    win:Show()
end

-- banc d essai
function GD._window() return win, stageRows, stepRows, function() return shownPart end end
