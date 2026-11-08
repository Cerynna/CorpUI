--[[--------------------------------------------------------------------------
    CorpUI - module Guide : le suivi a l ecran

    En-tete : partie du guide (numero, tranche de niveaux et lieu), etape
    sur le total ; boutons : etape d avant, valider l etape (suivante),
    ouvrir le guide. Dessous : l etape en cours en couleurs (quetes a
    prendre en or, a rendre en vert, a faire en bleu ; PNJ en vert,
    monstres en rouge, objets en violet, lieux en orange), sa remarque,
    puis les suivantes en plus pale (nombre au choix).
      clic sur des coordonnees : la fleche y va ;
      clic sur une etape suivante : elle devient l etape en cours ;
      clic droit sur l etape en cours : la valider.
    Fond obsidienne (opacite au choix). Deplacable avec "Deverrouiller
    l interface".
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local GD = ns.Guide

local HEAD_H = 24
local PAD = 6
local MAX_AHEAD = 4
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"

local frame, header, rows, db

local function width() return (db and db.width) or 320 end

local function iconButton(parent, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        local t = ns.Tooltip(self, "ANCHOR_TOP")
        t:AddLine(tip, 1, 1, 1)
        t:Show()
    end)
    b:SetScript("OnLeave", ns.HideTooltip)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)
    return b
end

-- clic sur un lien de coordonnees d une ligne
local function onLink(self, link)
    local i = tonumber((link or ""):match("^corpguide:(%d+)$"))
    if not (i and self.p) then return end
    if not self.current then GD.GoToStep(self.p, self.s) end
    GD.Aim(i)
end

local function onRowClick(self, button)
    if not self.p then return end
    if button == "RightButton" then
        if self.current then GD.ValidateStep() end
        return
    end
    if not self.current then GD.GoToStep(self.p, self.s) end
end

local function rowTip(self)
    if not self.p then return end
    local t = ns.Tooltip(self, "ANCHOR_LEFT")
    t:AddLine(self.current and L.GUIDE_TIP_CURRENT or L.GUIDE_TIP_NEXT, 0.8, 0.8, 0.8, true)
    t:AddLine(L.GUIDE_TIP_COORDS, 0.6, 0.7, 1, true)
    t:Show()
end

local function row(i)
    if rows[i] then return rows[i] end
    local C = ns.COLORS
    local r = CreateFrame("Button", nil, frame)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pcall(r.SetHyperlinksEnabled, r, true)
    r:SetScript("OnHyperlinkClick", onLink)
    r.mark = r:CreateTexture(nil, "BACKGROUND")
    r.mark:SetPoint("TOPLEFT", -PAD + 1, 2)
    r.mark:SetPoint("BOTTOMRIGHT", PAD - 1, -2)
    ns.UI.Gradient(r.mark, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.22, C.violet[1], C.violet[2], C.violet[3], 0)
    r.num = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.num:SetPoint("TOPLEFT", 0, -1)
    r.num:SetWidth(22)
    r.num:SetJustifyH("RIGHT")
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetPoint("TOPLEFT", 26, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(true)
    r.note = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.note:SetJustifyH("LEFT")
    r.note:SetWordWrap(true)
    r.note:SetTextColor(0.72, 0.72, 0.72)
    r:SetScript("OnClick", onRowClick)
    r:SetScript("OnEnter", rowTip)
    r:SetScript("OnLeave", ns.HideTooltip)
    rows[i] = r
    return r
end

-- une etape ; renvoie la hauteur
local function fill(r, p, s, st, current, y)
    local w = width() - PAD * 2
    r.p, r.s, r.current = p, s, current
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
    r:SetWidth(w)
    r.mark:SetShown(current)
    r:SetAlpha(current and 1 or 0.62)
    r.num:SetText(string.format("%02d)", s))
    r.text:SetWidth(w - 26)
    r.text:SetFontObject(current and "GameFontHighlight" or "GameFontHighlightSmall")
    r.text:SetText(st.text)
    local h = math.max(12, r.text:GetStringHeight() or 0)
    if st.note and current then
        r.note:ClearAllPoints()
        r.note:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
        r.note:SetWidth(w - 26)
        r.note:SetText(L.GUIDE_NOTE .. " " .. st.note)
        r.note:Show()
        h = h + 3 + math.max(10, r.note:GetStringHeight() or 0)
    else
        r.note:Hide()
    end
    r:SetHeight(h)
    r:Show()
    return h
end

function GD.DrawTracker()
    if not frame then return end
    local show = db.show and (GD.g ~= nil or not GD.Data() or ns.moversShown)
    if not show then
        frame:Hide()
        return
    end
    frame:SetWidth(width())
    if frame.cuiBg then frame.cuiBg:SetAlpha(db.alpha or 0.75) end
    local g, prog = GD.g, GD.prog
    local y = HEAD_H + 6
    local used = 0
    frame.msg:Hide()
    if not GD.Data() or not g then
        header.title:SetText(L.MOD_GUIDE)
        header.count:SetText("")
        frame.msg:SetText(GD.Data() and L.GUIDE_NONE or L.GUIDE_NO_DATA)
    elseif prog.p > #g.e then
        local e = GD.Stage(g, #g.e)
        header.title:SetText(e and e[1] or L.MOD_GUIDE)
        header.count:SetText(string.format("%d / %d", GD.Total(g), GD.Total(g)))
        frame.msg:SetText(L.GUIDE_FINISHED)
    else
        local e = GD.Stage(g, prog.p)
        header.title:SetText(string.format(L.GUIDE_PART, prog.p, #g.e, e[1]))
        header.count:SetText(string.format("%d / %d", GD.Index(g, prog.p, prog.s), GD.Total(g)))
        local p, s = prog.p, prog.s
        local n = 1 + math.max(0, math.min(MAX_AHEAD, db.ahead or 2))
        local guard = 0
        while p and used < n and guard < 40 do
            guard = guard + 1
            local st, stage = GD.StepAt(g, p, s)
            if not st then break end
            -- etape suivante deja faite (cochee, quete rendue...) : pas montree
            if used == 0 or not GD.Done(g, prog, p, s) then
                used = used + 1
                y = y + fill(row(used), p, s, st, used == 1, y) + 6
            end
            -- changement de partie : son titre
            p, s = GD.NextPos(g, p, s)
            if p and s == 1 and used < n then
                local ne = GD.Stage(g, p)
                if ne and stage ~= ne then
                    used = used + 1
                    local r = row(used)
                    r.p, r.s, r.current = nil, nil, false
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
                    r:SetWidth(width() - PAD * 2)
                    r.mark:Hide()
                    r:SetAlpha(0.62)
                    r.num:SetText("")
                    r.note:Hide()
                    r.text:SetWidth(width() - PAD * 2 - 26)
                    r.text:SetFontObject("GameFontNormalSmall")
                    r.text:SetText(string.format(L.GUIDE_NEXT_PART, ne[1]))
                    local h = math.max(12, r.text:GetStringHeight() or 0)
                    r:SetHeight(h)
                    r:Show()
                    y = y + h + 6
                end
            end
        end
    end
    for i = used + 1, #rows do
        rows[i]:Hide()
        rows[i].p = nil
    end
    if used == 0 then
        frame.msg:ClearAllPoints()
        frame.msg:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
        frame.msg:SetWidth(width() - PAD * 2)
        frame.msg:Show()
        y = y + math.max(12, frame.msg:GetStringHeight() or 0) + 6
    end
    header.back:SetEnabled(g ~= nil and (prog.p > 1 or prog.s > 1))
    header.ok:SetEnabled(g ~= nil and prog.p <= #g.e)
    frame:SetHeight(y + 2)
    frame:Show()
end

function GD.BuildTracker(options)
    db = options
    db.pos = db.pos or { point = "TOPRIGHT", x = -260, y = -220 }
    frame = CreateFrame("Frame", "CorpUIGuideTracker", UIParent)
    frame:SetSize(width(), HEAD_H + 40)
    frame:SetFrameStrata("LOW")
    ns.ApplyPos(frame, db.pos)
    ns.UI.Skin(frame, db.alpha or 0.75)
    rows = {}

    header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEAD_H)
    local rule = header:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT", PAD, 0)
    rule:SetPoint("BOTTOMRIGHT", -PAD, 0)
    rule:SetHeight(1)
    ns.NoSnap(rule)
    rule:SetColorTexture(1, 1, 1, 0.18)
    header.open = iconButton(header, L.GUIDE_OPEN, function() GD.ToggleWindow() end)
    header.open:SetPoint("RIGHT", -4, 0)
    local book = header.open:CreateTexture(nil, "ARTWORK")
    book:SetAllPoints()
    book:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    book:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    header.ok = iconButton(header, L.GUIDE_VALIDATE, function() GD.ValidateStep() end)
    header.ok:SetPoint("RIGHT", header.open, "LEFT", -4, 0)
    local tick = header.ok:CreateTexture(nil, "ARTWORK")
    tick:SetAllPoints()
    tick:SetTexture(CHECK)
    header.ok:SetScript("OnDisable", function() tick:SetDesaturated(true) tick:SetAlpha(0.4) end)
    header.ok:SetScript("OnEnable", function() tick:SetDesaturated(false) tick:SetAlpha(1) end)
    header.back = iconButton(header, L.GUIDE_BACK, function() GD.BackStep() end)
    header.back:SetPoint("RIGHT", header.ok, "LEFT", -4, 0)
    local chev = ns.UI.Chevron(header.back, 12, "LEFT")
    chev:SetPoint("CENTER")
    header.back:SetScript("OnDisable", function() chev:SetAlpha(0.35) end)
    header.back:SetScript("OnEnable", function() chev:SetAlpha(1) end)
    header.count = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header.count:SetPoint("RIGHT", header.back, "LEFT", -6, 0)
    header.title = header:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(header.title, 12)
    header.title:SetPoint("LEFT", PAD, 0)
    header.title:SetPoint("RIGHT", header.count, "LEFT", -6, 0)
    header.title:SetJustifyH("LEFT")
    header.title:SetWordWrap(false)
    header.title:SetTextColor(ns.COLORS.gold[1], ns.COLORS.gold[2], ns.COLORS.gold[3])

    frame.msg = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.msg:SetJustifyH("LEFT")
    frame.msg:SetWordWrap(true)
    frame:Hide()
    ns.UI.Mover(frame, db.pos, L.MOD_GUIDE)
end

-- banc d essai
function GD._tracker() return frame, header, rows end
