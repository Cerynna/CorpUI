--[[--------------------------------------------------------------------------
    CorpUI - module Compteur (notre "Details")
    Fenetres de compteur a nous, aussi nombreuses qu on veut, chacune avec
    son mode et son segment. Source : C_DamageMeter (le compteur du jeu
    continue de compter en arriere-plan ; sa fenetre est masquee).

    Ce que le client laisse lire (sonde du 05/10) :
      - hors combat : tout (noms, montants, detail par sort et par cible) ;
      - en combat : la liste, son ordre, la classe, la specialisation, "c est
        moi" ; noms et montants sont secrets : on les donne tels quels aux
        barres et aux textes (permis), sans calcul (pas de %) ; le detail
        d un autre joueur est refuse (son identifiant est secret), le notre
        passe par UnitGUID("player").
      - le journal de combat brut est interdit aux addons.

    Modes : degats, DPS, soins, HPS, absorptions, interruptions,
    dissipations, degats subis, degats evitables, morts, degats des ennemis.
    Segments : combat en cours, global, et les combats precedents gardes
    par le jeu (C_DamageMeter.GetAvailableCombatSessions).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS

local issecret = issecretvalue or function() return false end

local DM = C_DamageMeter
local T = Enum and Enum.DamageMeterType or {}
local ST = Enum and Enum.DamageMeterSessionType or {}

-- modes dans l ordre du menu ; ps : valeur par seconde en premier ;
-- nops : pas de valeur par seconde ; label : texte du jeu, sinon le notre
local MODES = {
    { key = "DamageDone", label = "DAMAGE_METER_TYPE_DAMAGE_DONE" },
    { key = "Dps", label = "DAMAGE_METER_TYPE_DPS", ps = true },
    { key = "HealingDone", label = "DAMAGE_METER_TYPE_HEALING_DONE" },
    { key = "Hps", label = "DAMAGE_METER_TYPE_HPS", ps = true },
    { key = "Absorbs", label = "DAMAGE_METER_TYPE_ABSORBS" },
    { key = "Interrupts", label = "DAMAGE_METER_TYPE_INTERRUPTS", nops = true },
    { key = "Dispels", label = "DAMAGE_METER_TYPE_DISPELS", nops = true },
    { key = "DamageTaken", label = "DAMAGE_METER_TYPE_DAMAGE_TAKEN" },
    { key = "AvoidableDamageTaken", label = "DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN" },
    { key = "Deaths", label = "DAMAGE_METER_TYPE_DEATHS", nops = true, deaths = true },
    { key = "EnemyDamageTaken", label = "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN", noIcon = true },
}
local MODE_BY_KEY = {}
for _, m in ipairs(MODES) do MODE_BY_KEY[m.key] = m end

local function modeName(m)
    local g = _G[m.label]
    if type(g) == "string" and g ~= "" then return g end
    return L["CM_MODE_" .. m.key] or m.key
end

local HEADER_H = 22
local DEFAULTS = {
    enabled = true, hideBlizzard = true, barHeight = 18, barSpacing = 1, fontSize = 11,
    icons = true, classColors = true, rank = true, bgAlpha = 80, numbers = "full", locked = false,
    texture = "corpui", show = "always", snap = true, tooltip = true,
}

-- textures des barres
local TEXTURES = {
    corpui = function() return ns.BAR_TEXTURE end,
    blizzard = function() return "Interface\\TargetingFrame\\UI-StatusBar" end,
    flat = function() return "Interface\\Buttons\\WHITE8X8" end,
    raid = function() return "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" end,
}
local TEXTURE_KEYS = { "corpui", "blizzard", "flat", "raid" }
local SHOW_KEYS = { "always", "combat", "group", "combatgroup" }
local SNAP = 12

local db
local windows = {}      -- objets fenetre
local detail            -- fenetre de detail (une seule)
local dirty = true

---------------------------------------------------------------------------
-- Lectures
---------------------------------------------------------------------------

-- (issecret d abord : comparer une valeur secrete, meme a nil, est interdit)
local function readable(v)
    if issecret(v) then return false end
    return v ~= nil
end

local function field(t, k)
    local ok, v = pcall(function() return t[k] end)
    if ok then return v end
end

-- nombre abrege, meme secret (le client sait abreger une valeur secrete) ;
-- lisible : 320.93M, 12.4K, comme Details
local function abbr(v)
    if v == nil then return "" end
    if readable(v) and type(v) == "number" then
        local a = math.abs(v)
        if a >= 1e9 then return string.format("%.2fB", v / 1e9) end
        if a >= 1e6 then return string.format("%.2fM", v / 1e6) end
        if a >= 1e4 then return string.format("%.1fK", v / 1e3) end
        if a >= 100 then return tostring(math.floor(v + 0.5)) end
        return (string.format("%.1f", v):gsub("%.0$", ""))
    end
    local fn = AbbreviateLargeNumbers or AbbreviateNumbers
    if fn then
        local ok, s = pcall(fn, v)
        if ok then return s end
    end
    if readable(v) then return tostring(math.floor(v + 0.5)) end
    return ""
end

local function sessionTypeOf(sess)
    if sess == "overall" then return ST.Overall end
    if sess == "current" then return ST.Current end
end

local function fetch(modeKey, sess)
    if not DM then return nil end
    local t = T[modeKey]
    if t == nil then return nil end
    local st = sessionTypeOf(sess)
    local ok, s
    if st then
        ok, s = pcall(DM.GetCombatSessionFromType, st, t)
    else
        ok, s = pcall(DM.GetCombatSessionFromID, sess, t)
    end
    if ok and (issecret(s) or type(s) == "table") then return s end
end

local function fetchSource(modeKey, sess, guid, creatureID)
    if not DM then return nil end
    local t = T[modeKey]
    local st = sessionTypeOf(sess)
    local ok, s
    if st then
        ok, s = pcall(DM.GetCombatSessionSourceFromType, st, t, guid, creatureID)
    else
        ok, s = pcall(DM.GetCombatSessionSourceFromID, sess, t, guid, creatureID)
    end
    if ok and (issecret(s) or type(s) == "table") then return s end
end

local function sources(session)
    local list = session and field(session, "combatSources")
    if type(list) == "table" then return list end
    return {}
end

local function fmtTime(sec)
    if not readable(sec) or type(sec) ~= "number" then return "" end
    sec = math.floor(sec + 0.5)
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- nom court d un segment
local function sessionLabel(sess)
    if sess == "current" then return L.CM_CURRENT end
    if sess == "overall" then return L.CM_OVERALL end
    if DM and DM.GetAvailableCombatSessions then
        local ok, list = pcall(DM.GetAvailableCombatSessions)
        if ok and type(list) == "table" then
            for i, s in ipairs(list) do
                if field(s, "sessionID") == sess then
                    local name = field(s, "name")
                    return (readable(name) and name ~= "" and name) or ("#" .. i)
                end
            end
        end
    end
    return "?"
end

-- couleur de classe d une source (le nom de classe n est jamais secret)
local function classColor(src)
    local cls = field(src, "classFilename")
    local c = readable(cls) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    if c and db.classColors then return c.r, c.g, c.b end
    return C.violet[1], C.violet[2], C.violet[3]
end

---------------------------------------------------------------------------
-- Une ligne (barre)
---------------------------------------------------------------------------

local function makeRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0.35)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("LEFT")
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetStatusBarTexture(ns.BAR_TEXTURE)
    r.bar:SetPoint("TOPRIGHT")
    r.bar:SetPoint("BOTTOMRIGHT")
    r.bar:SetMinMaxValues(0, 1)
    r.text = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 4, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.value = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.value:SetPoint("RIGHT", -4, 0)
    r.value:SetJustifyH("RIGHT")
    r.text:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    return r
end

local function styleRow(r)
    local h = db.barHeight
    local tex = (TEXTURES[db.texture] or TEXTURES.corpui)()
    if r.texKey ~= tex then
        r.bar:SetStatusBarTexture(tex)
        r.texKey = tex
    end
    r:SetHeight(h)
    r.icon:SetSize(h, h)
    r.icon:SetShown(db.icons)
    r.bar:ClearAllPoints()
    r.bar:SetPoint("TOPRIGHT")
    r.bar:SetPoint("BOTTOMRIGHT")
    r.bar:SetPoint("LEFT", db.icons and r.icon or r, db.icons and "RIGHT" or "LEFT", db.icons and 1 or 0, 0)
    local font = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    pcall(r.text.SetFont, r.text, font, db.fontSize, "OUTLINE")
    pcall(r.value.SetFont, r.value, font, db.fontSize, "OUTLINE")
end

-- texte de valeur : principal (par seconde en premier pour DPS / HPS), puis
-- secondaire et pourcentage quand on peut les calculer
local function setValueText(r, mode, src, total)
    if mode.deaths then
        r.value:SetText(fmtTime(field(src, "deathTimeSeconds")))
        return
    end
    local amount = field(src, "totalAmount")
    local ps = field(src, "amountPerSecond")
    local main, second = amount, ps
    if mode.ps then main, second = ps, amount end
    if mode.nops then second = nil end
    local pct
    if db.numbers == "full" and readable(amount) and readable(total) and type(total) == "number" and total > 0 then
        pct = amount / total * 100
    end
    local a, b = abbr(main), second ~= nil and abbr(second) or nil
    local ok
    if db.numbers == "short" or not b then
        ok = pcall(r.value.SetFormattedText, r.value, "%s", a)
    elseif pct then
        ok = pcall(r.value.SetFormattedText, r.value, "%s (%s, %.1f%%)", a, b, pct)
    else
        ok = pcall(r.value.SetFormattedText, r.value, "%s (%s)", a, b)
    end
    if not ok then r.value:SetText("") end
end

local function fillRow(r, w, mode, src, index, session)
    r.src, r.index = src, index
    local cr, cg, cb = classColor(src)
    r.bar:SetStatusBarColor(cr, cg, cb, 1)
    local fill = r.bar:GetStatusBarTexture()
    if fill then ns.UI.Gradient(fill, "HORIZONTAL", cr * 0.55, cg * 0.55, cb * 0.55, 1, cr, cg, cb, 1) end
    -- icone : specialisation, sinon classe
    local spec = field(src, "specIconID")
    local cls = field(src, "classFilename")
    if mode.noIcon then
        r.icon:SetTexture(nil)
    elseif readable(spec) and spec ~= 0 then
        r.icon:SetTexture(spec)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif readable(cls) and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls] then
        r.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        r.icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[cls]))
    else
        r.icon:SetTexture(nil)
    end
    -- barre : rapport au plus haut, le client compare (valeurs secretes permises)
    local max = field(session, "maxAmount")
    local amount = field(src, "totalAmount")
    if not (pcall(r.bar.SetMinMaxValues, r.bar, 0, max) and pcall(r.bar.SetValue, r.bar, amount)) then
        r.bar:SetMinMaxValues(0, 1)
        r.bar:SetValue(0)
    end
    local name = field(src, "name")
    local okN
    if db.rank then
        okN = pcall(r.text.SetFormattedText, r.text, "%d. %s", index, name)
    else
        okN = pcall(r.text.SetFormattedText, r.text, "%s", name)
    end
    if not okN then r.text:SetText("?") end
    setValueText(r, mode, src, field(session, "totalAmount"))
    r:Show()
end

---------------------------------------------------------------------------
-- Fenetre de detail : sorts d un joueur (et cibles au survol)
---------------------------------------------------------------------------

local DETAIL_W, DETAIL_ROWS = 340, 16

local function buildDetail()
    local f = CreateFrame("Frame", "CorpUIMeterDetail", UIParent, "BackdropTemplate")
    f:SetSize(DETAIL_W, HEADER_H + DETAIL_ROWS * 17 + 8)
    f:SetPoint("CENTER", 200, 0)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    ns.UI.SetBackdrop(f, 0.95)
    ns.UI.Shadow(f, 4)
    f.title = f:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(f.title, 12)
    f.title:SetPoint("TOPLEFT", 8, -5)
    f.title:SetPoint("RIGHT", -26, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    local close = ns.UI.Button(f, "x", 18, function() f:Hide() end)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -3, -2)
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.note:SetPoint("TOPLEFT", 8, -HEADER_H - 6)
    f.note:SetPoint("RIGHT", -8, 0)
    f.note:SetJustifyH("LEFT")
    f.rows = {}
    for i = 1, DETAIL_ROWS do
        local r = makeRow(f)
        r:SetPoint("TOPLEFT", 4, -HEADER_H - (i - 1) * 17)
        r:SetPoint("RIGHT", -4, 0)
        r:SetScript("OnEnter", function(self)
            if not self.spell then return end
            local t = GameTooltip
            t:SetOwner(self, "ANCHOR_RIGHT")
            local id = field(self.spell, "spellID")
            if not pcall(t.SetSpellByID, t, id) then t:AddLine(self.text:GetText() or "") end
            -- repartition par cible
            local det = field(self.spell, "combatSpellDetails")
            local list = {}
            if type(det) == "table" then
                if field(det, "unitName") ~= nil then list = { det } else list = det end
            end
            local any = false
            for _, u in ipairs(list) do
                local n, a = field(u, "unitName"), field(u, "amount")
                -- le jeu laisse souvent cette entree vide : seulement un vrai nom
                local real = issecret(n) or (type(n) == "string" and n ~= "")
                if real and not (readable(a) and a == 0) then
                    if not any then t:AddLine(" ") t:AddLine(L.CM_TARGETS, C.gold[1], C.gold[2], C.gold[3]) any = true end
                    pcall(t.AddDoubleLine, t, n, abbr(a), 1, 1, 1, 1, 1, 1)
                end
            end
            t:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.rows[i] = r
    end
    f:Hide()
    return f
end

local function refreshDetail()
    if not detail or not detail:IsShown() or not detail.want then return end
    local want = detail.want
    local mode = MODE_BY_KEY[want.mode]
    local guid = want.guid
    -- en combat, seul notre propre detail est accessible
    if want.isMe then guid = UnitGUID("player") end
    local srcData = fetchSource(want.mode, want.session, guid, want.creatureID)
    local spells = srcData and field(srcData, "combatSpells")
    if type(spells) ~= "table" then spells = {} end
    local ok, n = pcall(function() return #spells end)
    n = ok and n or 0
    detail.note:SetShown(n == 0)
    detail.note:SetText(n == 0 and (InCombatLockdown() and L.CM_DETAIL_COMBAT or L.CM_DETAIL_NONE) or "")
    local total = srcData and field(srcData, "totalAmount")
    local max = srcData and field(srcData, "maxAmount")
    for i, r in ipairs(detail.rows) do
        local sp = i <= n and spells[i]
        if sp then
            styleRow(r)
            r:SetHeight(16)
            r.spell = sp
            local id = field(sp, "spellID")
            local okT, tex = false, nil
            if C_Spell and C_Spell.GetSpellTexture then okT, tex = pcall(C_Spell.GetSpellTexture, id) end
            if not (okT and pcall(r.icon.SetTexture, r.icon, tex)) then r.icon:SetTexture(nil) end
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local okName, name = false, nil
            if C_Spell and C_Spell.GetSpellName then okName, name = pcall(C_Spell.GetSpellName, id) end
            local creature = field(sp, "creatureName")
            if not (okName and pcall(r.text.SetFormattedText, r.text, "%s", name)) then r.text:SetText("?") end
            if readable(creature) and creature ~= "" then
                pcall(r.text.SetFormattedText, r.text, "%s (%s)", name, creature)
            end
            r.bar:SetStatusBarColor(C.violet[1], C.violet[2], C.violet[3], 0.8)
            local amount = field(sp, "totalAmount")
            if not (pcall(r.bar.SetMinMaxValues, r.bar, 0, max) and pcall(r.bar.SetValue, r.bar, amount)) then
                r.bar:SetValue(0)
            end
            setValueText(r, mode, sp, total)
            r:Show()
        else
            r.spell = nil
            r:Hide()
        end
    end
end

local function openDetail(w, row)
    local src = row.src
    if not src then return end
    local mode = MODE_BY_KEY[w.conf.mode]
    if mode.deaths then
        local id = field(src, "deathRecapID")
        if readable(id) and id ~= 0 and OpenDeathRecapUI then pcall(OpenDeathRecapUI, id) end
        return
    end
    detail = detail or buildDetail()
    local isMe = field(src, "isLocalPlayer")
    local guid = field(src, "sourceGUID")
    detail.want = {
        mode = w.conf.mode, session = w.conf.session,
        isMe = readable(isMe) and isMe or false,
        guid = readable(guid) and guid or nil,
        creatureID = readable(field(src, "sourceCreatureID")) and field(src, "sourceCreatureID") or nil,
    }
    local name = field(src, "name")
    if not pcall(detail.title.SetFormattedText, detail.title, "%s - %s", name, modeName(mode)) then
        detail.title:SetText(modeName(mode))
    end
    detail:Show()
    refreshDetail()
end

---------------------------------------------------------------------------
-- Fenetres
---------------------------------------------------------------------------

local function windowAlpha(f)
    local a = db.bgAlpha / 100
    f:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], a)
end

-- segments du menu : en cours, global, puis les combats gardes par le jeu
local function sessionOptions()
    local list = { { value = "current", text = sessionLabel("current") }, { value = "overall", text = sessionLabel("overall") } }
    if DM and DM.GetAvailableCombatSessions then
        local ok, all = pcall(DM.GetAvailableCombatSessions)
        if ok and type(all) == "table" then
            for i = #all, 1, -1 do
                local s = all[i]
                local id, name, dur = field(s, "sessionID"), field(s, "name"), field(s, "durationSeconds")
                if readable(id) then
                    local text = (readable(name) and name ~= "" and name) or ("#" .. i)
                    if readable(dur) then text = text .. "  |cff999999" .. fmtTime(dur) .. "|r" end
                    table.insert(list, { value = id, text = text })
                end
            end
        end
    end
    list.width = 220
    return list
end

local refreshWindow
local rowTooltip

-- infobulle d une barre : nom, valeurs, et les 3 premiers sorts quand le
-- jeu les donne (hors combat ; en combat, seulement les notres)
rowTooltip = function(w, r)
    if not db.tooltip or not r.src then return end
    local src = r.src
    local mode = MODE_BY_KEY[w.conf.mode]
    local tip = GameTooltip
    tip:SetOwner(r, "ANCHOR_LEFT")
    local cr, cg, cb = classColor(src)
    if not pcall(tip.AddLine, tip, field(src, "name"), cr, cg, cb) then tip:AddLine("?") end
    pcall(tip.AddDoubleLine, tip, modeName(mode), abbr(field(src, "totalAmount")), 1, 0.82, 0, 1, 1, 1)
    if not mode.nops then
        pcall(tip.AddDoubleLine, tip, L.CM_PER_SECOND, abbr(field(src, "amountPerSecond")), 1, 0.82, 0, 1, 1, 1)
    end
    if not mode.deaths then
        local isMe = field(src, "isLocalPlayer")
        local guid = (readable(isMe) and isMe) and UnitGUID("player") or field(src, "sourceGUID")
        local data = readable(guid) and fetchSource(w.conf.mode, w.conf.session, guid) or nil
        local spells = data and field(data, "combatSpells")
        if type(spells) == "table" and spells[1] then
            tip:AddLine(" ")
            for i = 1, math.min(3, #spells) do
                local sp = spells[i]
                local id = field(sp, "spellID")
                local okN, name = false, nil
                if C_Spell and C_Spell.GetSpellName then okN, name = pcall(C_Spell.GetSpellName, id) end
                local okT, tex = false, nil
                if C_Spell and C_Spell.GetSpellTexture then okT, tex = pcall(C_Spell.GetSpellTexture, id) end
                local icon = (okT and readable(tex)) and ("|T" .. tex .. ":14:14:0:0:64:64:5:59:5:59|t ") or ""
                local label = (okN and readable(name)) and (icon .. name) or "?"
                pcall(tip.AddDoubleLine, tip, label, abbr(field(sp, "totalAmount")), 1, 1, 1, 1, 1, 1)
            end
        end
    end
    tip:AddLine(L.CM_TIP_CLICK, 0.6, 0.6, 0.6)
    tip:Show()
end

local function report(w, channel)
    if InCombatLockdown() then ns.Say(L.CM_REPORT_COMBAT) return end
    local mode = MODE_BY_KEY[w.conf.mode]
    local session = fetch(w.conf.mode, w.conf.session)
    local list = sources(session)
    local total = field(session, "totalAmount")
    local lines = { string.format("CorpUI - %s (%s)", modeName(mode), sessionLabel(w.conf.session)) }
    for i = 1, math.min(#list, 8) do
        local s = list[i]
        local name, amount = field(s, "name"), field(s, "totalAmount")
        if readable(name) and readable(amount) then
            local pct = (readable(total) and total > 0) and string.format(" (%.0f%%)", amount / total * 100) or ""
            table.insert(lines, string.format("%d. %s  %s%s", i, name, abbr(amount), pct))
        end
    end
    for _, line in ipairs(lines) do pcall(SendChatMessage, line, channel) end
end

local function reportOptions()
    local list = {}
    if IsInRaid() then table.insert(list, { value = "report:RAID", text = RAID or "Raid" }) end
    if IsInGroup() and not IsInRaid() then table.insert(list, { value = "report:PARTY", text = PARTY or "Group" }) end
    if IsInGuild() then table.insert(list, { value = "report:GUILD", text = GUILD or "Guild" }) end
    table.insert(list, { value = "report:SAY", text = SAY or "Say" })
    list.width = 150
    return list
end

local function resetOptions()
    return { { value = "reset", text = L.CM_RESET }, width = 190 }
end

local function optionsOptions()
    return {
        { value = "lock", text = db.locked and L.CM_UNLOCK or L.CM_LOCK },
        { value = "close", text = L.CM_CLOSE_WINDOW },
        { value = "options", text = L.CM_OPTIONS },
        width = 190,
    }
end

local function modeOptions()
    local list = {}
    for _, m in ipairs(MODES) do table.insert(list, { value = m.key, text = modeName(m) }) end
    list.width = 190
    return list
end

local createWindow
local snapWindow

-- Aimantation : une fenetre lachee pres d une autre s y colle (dessus,
-- dessous ou a cote), bords alignes. Maj : pas d aimantation.
snapWindow = function(w)
    local f = w.f
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (l and t) then return end
    local width, height = r - l, t - b
    local best, bx, by
    for _, o in ipairs(windows) do
        if o ~= w and o.f:IsShown() then
            local ol, or_, ot, ob = o.f:GetLeft(), o.f:GetRight(), o.f:GetTop(), o.f:GetBottom()
            if ol then
                local cands = {}
                local hOverlap = l < or_ + SNAP and r > ol - SNAP
                local vOverlap = b < ot + SNAP and t > ob - SNAP
                if hOverlap then
                    table.insert(cands, { math.abs(b - ot), ol, ot + height })       -- dessus
                    table.insert(cands, { math.abs(t - ob), ol, ob })                -- dessous
                end
                if vOverlap then
                    table.insert(cands, { math.abs(r - ol), ol - width, ot })        -- a gauche
                    table.insert(cands, { math.abs(l - or_), or_, ot })              -- a droite
                end
                for _, c in ipairs(cands) do
                    if c[1] <= SNAP and (not best or c[1] < best) then best, bx, by = c[1], c[2], c[3] end
                end
            end
        end
    end
    if best then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", bx, by)
    end
end

local function doMenu(w, v)
    if v == "reset" then
        if DM and DM.ResetAllCombatSessions then pcall(DM.ResetAllCombatSessions) end
        dirty = true
    elseif v == "new" then
        local c = { mode = "HealingDone", session = "current", pos = { point = "CENTER", x = 40, y = -40 }, w = w.conf.w, h = w.conf.h }
        table.insert(db.windows, c)
        createWindow(c)
        dirty = true
    elseif v == "close" then
        if #db.windows <= 1 then ns.Say(L.CM_LAST_WINDOW) return end
        for i, c in ipairs(db.windows) do if c == w.conf then table.remove(db.windows, i) break end end
        for i, o in ipairs(windows) do if o == w then table.remove(windows, i) break end end
        w.f:Hide()
    elseif v == "lock" then
        db.locked = not db.locked
    elseif v == "options" then
        if ns.OpenMeterOptions then ns.OpenMeterOptions() end
    elseif type(v) == "string" and v:find("^report:") then
        report(w, v:sub(8))
    end
end

-- icone du bandeau (dessin CorpUI blanc, teint en or ; blanc au survol)
local function headerIcon(parent, file, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(14, 14)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexture(ns.MEDIA .. file)
    b.tex:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    b:SetScript("OnEnter", function(self)
        self.tex:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.tex:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
        GameTooltip:Hide()
    end)
    return b
end

-- textes cliquables du bandeau (mode, segment)
local function headerText(f, size)
    local b = CreateFrame("Button", nil, f)
    b:SetHeight(HEADER_H - 4)
    b.fs = b:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(b.fs, size)
    b.fs:SetAllPoints()
    b.fs:SetJustifyH("LEFT")
    b.fs:SetWordWrap(false)
    b:SetScript("OnEnter", function(self) self.fs:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function(self) self:Color() end)
    function b.Color(self) self.fs:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
    b:Color()
    return b
end

createWindow = function(conf)
    local w = { conf = conf, rows = {}, offset = 0 }
    if not MODE_BY_KEY[conf.mode] then conf.mode = "DamageDone" end
    if type(conf.session) ~= "string" then conf.session = "current" end
    conf.pos = conf.pos or { point = "BOTTOMRIGHT", x = -240, y = 200 }
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    w.f = f
    f:SetSize(conf.w or 230, conf.h or 160)
    ns.ApplyPos(f, conf.pos)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(140, HEADER_H + 30, 700, 700) end
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetFrameStrata("MEDIUM")
    ns.UI.SetBackdrop(f, 0.8)
    windowAlpha(f)

    -- bandeau : deplacement, mode, segment, menu
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(HEADER_H)
    local hbg = head:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    local line = head:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    if ns.MODERN then
        -- style Moderne : bandeau sombre et uni, sans filet d or
        hbg:SetColorTexture(0, 0, 0, 0.4)
        line:Hide()
    else
        ns.UI.Gradient(hbg, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.35, C.violet[1], C.violet[2], C.violet[3], 0.05)
        ns.UI.Gradient(line, "HORIZONTAL", C.gold[1], C.gold[2], C.gold[3], 0.7, C.gold[1], C.gold[2], C.gold[3], 0)
    end
    -- deplacement : tout le bandeau (textes compris) et le vide sous les barres
    local function dragStart() if not db.locked then f:StartMoving() end end
    local function dragStop()
        w.dragged = GetTime()     -- le relachement ne doit pas ouvrir un menu
        f:StopMovingOrSizing()
        if db.snap and not IsShiftKeyDown() then snapWindow(w) end
        ns.PinTop(f, conf.pos, true)
    end
    w.draggable = function(o)
        o:RegisterForDrag("LeftButton")
        o:SetScript("OnDragStart", dragStart)
        o:SetScript("OnDragStop", dragStop)
    end
    head:EnableMouse(true)
    w.draggable(head)
    w.draggable(f)

    -- barre d icones, de droite a gauche
    local function menu(btn, opts, get, set)
        ns.UI.OpenMenu(btn, opts, get or function() return nil end, set)
    end
    local icons = {
        { "meter_options", L.CM_OPTIONS, function(self) menu(self, optionsOptions, nil, function(v) doMenu(w, v) end) end },
        { "meter_new", L.CM_NEW_WINDOW, function() doMenu(w, "new") end },
        { "meter_reset", L.CM_RESET, function(self) menu(self, resetOptions, nil, function(v) doMenu(w, v) end) end },
        { "meter_report", L.CM_REPORT, function(self) menu(self, reportOptions, nil, function(v) doMenu(w, v) end) end },
        { "meter_mode", L.CM_MODE, function(self)
            menu(self, modeOptions, function() return conf.mode end, function(v) conf.mode = v w.offset = 0 dirty = true end)
        end },
        { "meter_segment", L.CM_SEGMENT, function(self)
            menu(self, sessionOptions, function() return conf.session end, function(v) conf.session = v dirty = true end)
        end },
    }
    local last
    for _, ic in ipairs(icons) do
        local b = headerIcon(head, ic[1], ic[2])
        if last then b:SetPoint("RIGHT", last, "LEFT", -5, 0) else b:SetPoint("RIGHT", -5, 0) end
        b:SetScript("OnClick", ic[3])
        last = b
    end
    -- titre : mode (clic : liste des modes), segment en gris
    w.mode = headerText(head, 11)
    w.mode:SetPoint("LEFT", 6, 0)
    w.mode:SetPoint("RIGHT", last, "LEFT", -6, 0)
    w.draggable(w.mode)
    w.mode:SetScript("OnClick", function(self)
        if w.dragged and GetTime() - w.dragged < 0.3 then return end
        menu(self, modeOptions, function() return conf.mode end, function(v) conf.mode = v w.offset = 0 dirty = true end)
    end)

    -- corps : lignes
    w.body = CreateFrame("Frame", nil, f)
    w.body:SetPoint("TOPLEFT", 2, -HEADER_H - 2)
    w.body:SetPoint("BOTTOMRIGHT", -2, 2)
    f:SetScript("OnMouseWheel", function(_, d)
        w.offset = math.max(0, w.offset - d)
        dirty = true
    end)

    -- poignee de taille
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    local gt = grip:CreateTexture(nil, "OVERLAY")
    gt:SetAllPoints()
    gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gt:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    grip:SetScript("OnMouseDown", function() if not db.locked then f:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        conf.w, conf.h = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
        ns.PinTop(f, conf.pos, true)
        dirty = true
    end)
    w.grip = grip
    f:SetScript("OnSizeChanged", function() dirty = true end)

    table.insert(windows, w)
    f:SetShown(db.enabled)
    return w
end

refreshWindow = function(w)
    local conf = w.conf
    local mode = MODE_BY_KEY[conf.mode]
    w.mode.fs:SetText(modeName(mode) .. "  |cff9a93aa" .. sessionLabel(conf.session) .. "|r")
    w.grip:SetShown(not db.locked)
    windowAlpha(w.f)
    local session = fetch(conf.mode, conf.session)
    local list = sources(session)
    local okN, n = pcall(function() return #list end)
    n = okN and n or 0
    local step = db.barHeight + db.barSpacing
    local visible = math.max(1, math.floor((w.body:GetHeight() + db.barSpacing) / step))
    w.offset = math.max(0, math.min(w.offset, n - visible))
    -- notre ligne toujours visible (comme le compteur du jeu)
    local meIndex
    for i = 1, n do
        local me = field(list[i], "isLocalPlayer")
        if readable(me) and me then meIndex = i break end
    end
    for i = 1, visible do
        local r = w.rows[i]
        if not r then
            r = makeRow(w.body)
            r:SetScript("OnClick", function(self, button)
                if button == "LeftButton" then openDetail(w, self) end
            end)
            r:SetScript("OnEnter", function(self) rowTooltip(w, self) end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            w.rows[i] = r
        end
        styleRow(r)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * step)
        r:SetPoint("RIGHT")
        local index = w.offset + i
        if i == visible and meIndex and (meIndex > w.offset + visible) and not MODE_BY_KEY[conf.mode].deaths then
            index = meIndex
        end
        local src = index <= n and list[index]
        if src then fillRow(r, w, mode, src, index, session) else r.src = nil r:Hide() end
    end
    for i = visible + 1, #w.rows do w.rows[i]:Hide() end
end

-- affichage selon le reglage : toujours, en combat, en groupe, ou les deux
local function wantShown()
    if not db.enabled then return false end
    if ns.moversShown then return true end
    local s = db.show
    local combat = InCombatLockdown() or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if s == "combat" then return combat and true or false end
    if s == "group" then return IsInGroup() end
    if s == "combatgroup" then return (combat or IsInGroup()) and true or false end
    return true
end

local function applyShown()
    local want = wantShown()
    for _, w in ipairs(windows) do
        if w.f:IsShown() ~= want then w.f:SetShown(want) end
    end
end

local function refreshAll()
    dirty = false
    if not db or not db.enabled then return end
    applyShown()
    for _, w in ipairs(windows) do
        if w.f:IsShown() then refreshWindow(w) end
    end
    refreshDetail()
end

---------------------------------------------------------------------------
-- Application des reglages
---------------------------------------------------------------------------

local function apply()
    if not db then return end
    applyShown()
    -- le compteur du jeu doit rester actif : c est notre source
    if db.enabled then pcall(SetCVar, "damageMeterEnabled", "1") end
    ns.HideBlizzard({ "DamageMeter" }, db.enabled and db.hideBlizzard)
    dirty = true
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local win

local function buildOptions()
    win = ns.UI.Window("CorpUIMeterOptions", ns.TITLE .. " - " .. L.MOD_METER, nil, 440, 300)
    local form = ns.UI.Form(win, -34, function() apply() end)
    local function check(key, text)
        form:Check(text, function() return db[key] end, function(v) db[key] = v end)
    end
    check("enabled", L.CM_OPT_ENABLE)
    check("hideBlizzard", L.CM_OPT_BLIZZ)
    -- habillage du compteur de Blizzard : reglage du module Degats
    -- (CorpUIDB.damage.enabled), applique par lui
    if ns.SetDamageStyle then
        form:Check(L.CM_OPT_BLIZZ_STYLE, function() return ns.DamageStyleEnabled() end,
            function(v) ns.SetDamageStyle(v) end)
    end

    -- apparence : barres, textes, couleurs, icones, fond
    form:Gap(4)
    form:Header(L.CM_H_LOOK)
    form:Columns(2)
    form:Number(L.CM_BAR_HEIGHT, function() return db.barHeight end, function(v) db.barHeight = v end, 10, 40)
    form:Number(L.CM_BAR_SPACING, function() return db.barSpacing end, function(v) db.barSpacing = v end, 0, 10)
    form:Number(L.CM_FONT_SIZE, function() return db.fontSize end, function(v) db.fontSize = v end, 7, 20)
    form:Number(L.CM_BG_ALPHA, function() return db.bgAlpha end, function(v) db.bgAlpha = v end, 0, 100, 5)
    check("icons", L.CM_OPT_ICONS)
    check("classColors", L.CM_OPT_CLASS)
    check("rank", L.CM_OPT_RANK)
    form:Cycle(L.CM_TEXTURE, TEXTURE_KEYS,
        { corpui = "CorpUI", blizzard = "Blizzard", flat = L.CM_TEX_FLAT, raid = L.CM_TEX_RAID },
        function() return db.texture end, function(v) db.texture = v end)
    form:EndColumns()

    -- comportement : quand l afficher, verrou, aimant, infobulle, nombres
    form:Gap(4)
    form:Header(L.CM_H_BEHAVIOR)
    form:Columns(2)
    form:Cycle(L.CM_SHOW, SHOW_KEYS,
        { always = L.CM_SHOW_ALWAYS, combat = L.CM_SHOW_COMBAT, group = L.CM_SHOW_GROUP, combatgroup = L.CM_SHOW_BOTH },
        function() return db.show end, function(v) db.show = v end)
    form:Cycle(L.CM_NUMBERS, { "short", "medium", "full" },
        { short = L.CM_NUM_SHORT, medium = L.CM_NUM_MEDIUM, full = L.CM_NUM_FULL },
        function() return db.numbers end, function(v) db.numbers = v end)
    check("locked", L.CM_OPT_LOCK)
    check("snap", L.CM_OPT_SNAP)
    check("tooltip", L.CM_OPT_TOOLTIP)
    form:EndColumns()

    -- fenetres : en ouvrir une, remettre les donnees a zero
    form:Gap(4)
    form:Header(L.CM_H_WINDOWS)
    local new = ns.UI.Button(win, L.CM_NEW_WINDOW, 150, function()
        if windows[1] then doMenu(windows[1], "new") end
    end)
    new:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y)
    local reset = ns.UI.Button(win, L.CM_RESET, 150, function()
        if DM and DM.ResetAllCombatSessions then pcall(DM.ResetAllCombatSessions) end
        dirty = true
    end)
    reset:SetPoint("LEFT", new, "RIGHT", 6, 0)
    form:Gap(30)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 4)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.CM_HINT)
    win:SetHeight(math.floor(80 - form.y))
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildOptions() end
    ns.ShowPanel(win)
end
ns.OpenMeterOptions = toggle

---------------------------------------------------------------------------
-- Evenements
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.meter = root.meter or {}
        db = root.meter
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        if type(db.windows) ~= "table" or #db.windows == 0 then
            db.windows = { { mode = "DamageDone", session = "current", pos = { point = "BOTTOMRIGHT", x = -240, y = 200 }, w = 230, h = 160 } }
        end
        for _, c in ipairs(db.windows) do createWindow(c) end
        apply()
    elseif db then
        dirty = true
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED",
                     "DAMAGE_METER_RESET", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- rafraichissement : sur evenement (au plus 5 fois par seconde), et chaque
-- seconde en combat (les valeurs par seconde bougent)
local since, tick = 0, 0
ev:SetScript("OnUpdate", function(_, dt)
    if not db or not db.enabled then return end
    since = since + dt
    tick = tick + dt
    if tick >= 1 and InCombatLockdown() then tick = 0 dirty = true end
    if dirty and since >= 0.2 then
        since = 0
        refreshAll()
    end
end)

ns.Listen(function() if db then dirty = true end end)

ns.RegisterModule({
    command = "compteur",
    panelName = "CorpUIMeterOptions",
    icon = "Interface\\Icons\\Ability_DualWield",
    title = function() return L.MOD_METER end,
    desc = function() return L.CM_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})
