--[[--------------------------------------------------------------------------
    CorpUI - podometre : la machine a sous (onglet du classeur)
      - les eclats (doublons des boosters) ne fabriquent plus de cartes : ils
        se jouent ici, mise 10, 20 ou 50 ;
      - trois rouleaux, six symboles, memes chances sur chaque rouleau :
        bottes, eclat, et quatre boosters (normal argent, rare bleu, epique
        violet, legendaire orange : variantes de booster.tga, make_boosters.js) ;
      - une seule combinaison par tour :
          trois boosters, toutes couleurs : un booster de la couleur la plus
            basse des trois (deux ou cinq avec la mise 20 ou 50) ;
          trois eclats : 8 fois la mise ; trois bottes : 3 fois ;
          deux eclats : la mise rendue ;
      - retour moyen 89 %, dont 54 % en boosters (un booster compte pour les
        eclats de ses doublons : calc_machine.js) ; booster 1 tour sur 16,
        rare 1 sur 107, epique 1 sur 829, legendaire 1 sur 8000 : la machine
        ne fabrique pas d eclats sans fin ;
      - tirage au lancer (P.SlotSpin : mise retiree, resultat garde dans
        db.slots.pending) ; gain verse a l arret des rouleaux (P.SlotSettle),
        ou en quittant l onglet, ou a la connexion suivante ;
      - rouleaux : bandes de symboles qui defilent vers le bas et s arretent
        l un apres l autre avec un rebond ; deux boosters sur les deux
        premiers : le troisieme tourne plus longtemps ; clic sur les
        rouleaux : arret immediat.
    Aucune action protegee.
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
local L = ns.L
local C = ns.COLORS

ns.Pedo = ns.Pedo or {}
local P = ns.Pedo

---------------------------------------------------------------------------
-- Regles et tirage
---------------------------------------------------------------------------

P.SLOT_BETS = { 10, 20, 50 }
P.SLOT_BASE = 10                     -- mise de reference (un booster)
P.SLOT_SYMBOLS = {
    { key = "boots", w = 34, icon = "INV_Boots_02" },
    { key = "shard", w = 24, icon = "INV_Enchant_ShardBrilliantLarge" },
    { key = "normal", w = 20, pack = 1 },
    { key = "rare", w = 11, pack = 2 },
    { key = "epic", w = 6, pack = 3 },
    { key = "legendary", w = 5, pack = 4 },
}
P.SLOT_PAY = { shard3 = 8, boots3 = 3, shard2 = 1 }   -- fois la mise
local PACK_KINDS = { "normal", "rare", "epic", "legendary" }

local SYM, WEIGHT = {}, 0
for _, s in ipairs(P.SLOT_SYMBOLS) do
    SYM[s.key] = s
    WEIGHT = WEIGHT + s.w
end

local function rollSymbol()
    local x = math.random() * WEIGHT
    for _, s in ipairs(P.SLOT_SYMBOLS) do
        x = x - s.w
        if x < 0 then return s.key end
    end
    return P.SLOT_SYMBOLS[#P.SLOT_SYMBOLS].key
end

-- gain de trois symboles pour une mise : { line, shards } ou
-- { line, kind, packs }, nil si perdu
function P.SlotPayout(a, b, c, bet)
    local sa, sb, sc = SYM[a], SYM[b], SYM[c]
    if not (sa and sb and sc) then return nil end
    if sa.pack and sb.pack and sc.pack then
        return { line = "packs", kind = PACK_KINDS[math.min(sa.pack, sb.pack, sc.pack)],
                 packs = math.max(1, math.floor(bet / P.SLOT_BASE)) }
    end
    if a == b and b == c and P.SLOT_PAY[a .. "3"] then
        return { line = a .. "3", shards = bet * P.SLOT_PAY[a .. "3"] }
    end
    local n = (a == "shard" and 1 or 0) + (b == "shard" and 1 or 0) + (c == "shard" and 1 or 0)
    if n == 2 then return { line = "shard2", shards = bet * P.SLOT_PAY.shard2 } end
end

-- chance de gagner un booster d une couleur : 1 tour sur N (mise de reference)
function P.SlotOdds(kind)
    local function q(min)
        local w = 0
        for _, s in ipairs(P.SLOT_SYMBOLS) do
            if s.pack and s.pack >= min then w = w + s.w end
        end
        return (w / WEIGHT) ^ 3
    end
    for i, k in ipairs(PACK_KINDS) do
        if k == kind then
            local p = q(i) - (i < #PACK_KINDS and q(i + 1) or 0)
            return p > 0 and math.floor(1 / p + 0.5) or nil
        end
    end
end

local function validBet(b)
    for _, v in ipairs(P.SLOT_BETS) do
        if v == b then return true end
    end
    return false
end

-- reglages et compteurs (CorpUIDB.pedometer.slots)
local function slotsDB()
    local d = P.db
    if not d then return nil end
    if type(d.slots) ~= "table" then d.slots = {} end
    local s = d.slots
    s.spins = tonumber(s.spins) or 0
    s.spent = tonumber(s.spent) or 0
    s.won = tonumber(s.won) or 0
    if type(s.packs) ~= "table" then s.packs = {} end
    if not validBet(s.bet) then s.bet = P.SLOT_BETS[1] end
    return s
end
P.SlotsDB = slotsDB

function P.SlotPacksWon()
    local s = slotsDB()
    local n = 0
    for _, v in pairs(s and s.packs or {}) do n = n + (tonumber(v) or 0) end
    return n
end

-- verse le gain du dernier tour (une fois)
function P.SlotSettle()
    local s = slotsDB()
    local p = s and s.pending
    if p == nil then return nil end
    s.pending = nil
    if type(p) ~= "table" then return nil end
    s.last = { r = p.r }
    local shards = tonumber(p.shards) or 0
    if shards > 0 then
        P.db.shards = (P.db.shards or 0) + shards
        s.won = s.won + shards
    end
    local packs = tonumber(p.packs) or 0
    if packs > 0 and SYM[p.kind] and P._givePack then
        for _ = 1, packs do P._givePack(p.kind, "slots", 0) end
        s.packs[p.kind] = (tonumber(s.packs[p.kind]) or 0) + packs
    end
    P.Changed("slots")
    return p
end

-- un tour : mise retiree, resultat tire et garde jusqu au versement
function P.SlotSpin(bet)
    local s = slotsDB()
    if not s then return nil end
    P.SlotSettle()
    bet = bet or s.bet
    if not validBet(bet) or (P.db.shards or 0) < bet then return nil end
    P.db.shards = P.db.shards - bet
    local r = { rollSymbol(), rollSymbol(), rollSymbol() }
    local win = P.SlotPayout(r[1], r[2], r[3], bet) or {}
    s.spins = s.spins + 1
    s.spent = s.spent + bet
    s.pending = { r = r, bet = bet, line = win.line, shards = win.shards, kind = win.kind, packs = win.packs }
    P.Changed("slots")
    return s.pending
end

---------------------------------------------------------------------------
-- Onglet : la machine, les gains
---------------------------------------------------------------------------

local MEDIA = ns.MEDIA .. "Podometre\\"
local ICON = "Interface\\Icons\\"
local TEX_PACK = 392 / 512
local PACK_RATIO = 1.5325
local PACK_FILE = { normal = "booster_normal", rare = "booster_rare", epic = "booster", legendary = "booster_legendaire" }
local PACK_RGB = { normal = { 0.9, 0.92, 0.96 }, rare = { 0.3, 0.6, 1 }, epic = { 0.75, 0.35, 1 }, legendary = { 1, 0.5, 0.1 } }
local CELL, REEL_W, REEL_GAP = 78, 112, 14      -- case d un rouleau, largeur, ecart
local ICON_SIZE, PACK_H = 54, 66
local WIND = 0.12                               -- elan (les rouleaux remontent un peu)
local STOP_AT = { 1.0, 1.45, 1.9 }              -- arret de chaque rouleau (s)
local TEASE_AT = 3.2                            -- le 3e, quand les deux premiers montrent un booster
local BOUNCE = 0.28
local SPIN_SPEED = 14                           -- symboles de la bande par seconde de rotation
local SPARKS = 24
local FX_TIME = 2.6

local page, reels, spin, fx

local function font(fs, size, flags)
    local f = (ns.FontFile and ns.FontFile("regular")) or STANDARD_TEXT_FONT
    pcall(fs.SetFont, fs, f, size, flags or "")
end

local function text(parent, template, size, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if size then font(fs, size, flags) end
    return fs
end

local function hex(rgb)
    return string.format("%02x%02x%02x", math.floor(rgb[1] * 255 + 0.5), math.floor(rgb[2] * 255 + 0.5),
        math.floor(rgb[3] * 255 + 0.5))
end

local function packName(kind)
    return L["PEDO_PACK_" .. string.upper(kind)] or kind
end

-- son du jeu (SOUNDKIT) ; ceux de CorpUI : P.Sound
local function kit(name)
    if not (P.db and P.db.opt.sound) then return end
    local id = SOUNDKIT and SOUNDKIT[name]
    if type(id) == "number" then pcall(PlaySound, id, "SFX") end
end

local function easeOutBack(k)
    local c = 1.7
    k = k - 1
    return 1 + (c + 1) * k * k * k + c * k * k
end

-- degrade vertical (couleurs du haut et du bas) ; repli : couleur unie
local function gradient(t, top, bottom)
    t:SetColorTexture(1, 1, 1, 1)
    if not (CreateColor and pcall(t.SetGradient, t, "VERTICAL", CreateColor(unpack(bottom)), CreateColor(unpack(top)))) then
        t:SetColorTexture((top[1] + bottom[1]) / 2, (top[2] + bottom[2]) / 2, (top[3] + bottom[3]) / 2, (top[4] + bottom[4]) / 2)
    end
end

-- cadre de 4 traits (lignes de gain)
local function outline(parent, layer, r, g, b, a, w)
    local edges = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                            { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = parent:CreateTexture(nil, layer)
        t:SetColorTexture(r, g, b, a)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if side[3] then t:SetHeight(w) else t:SetWidth(w) end
        edges[#edges + 1] = t
    end
    return edges
end

-- symbole : icone du jeu dans un liseré, ou booster de sa couleur
local function newSymbol(parent, icon, packH)
    local f = CreateFrame("Frame", nil, parent)
    f.iconBg = f:CreateTexture(nil, "BORDER")
    f.iconBg:SetPoint("CENTER")
    f.iconBg:SetSize(icon + 4, icon + 4)
    f.iconBg:SetColorTexture(0, 0, 0, 0.9)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("CENTER")
    f.icon:SetSize(icon, icon)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.pack = f:CreateTexture(nil, "ARTWORK")
    f.pack:SetPoint("CENTER")
    f.pack:SetTexCoord(0, 1, 0, TEX_PACK)
    f.iconSize, f.packH = icon, packH
    f.key = false
    return f
end

local function sizeSymbol(f, k)
    f.icon:SetSize(f.iconSize * k, f.iconSize * k)
    f.iconBg:SetSize((f.iconSize + 4) * k, (f.iconSize + 4) * k)
    f.pack:SetSize(f.packH / PACK_RATIO * k, f.packH * k)
end

local function paintSymbol(f, key)
    if f.key == key and key ~= nil then return end
    f.key = key
    local s = SYM[key]
    if not s then
        f.icon:Hide() f.iconBg:Hide() f.pack:Hide()
        return
    end
    if s.pack then
        f.icon:Hide()
        f.iconBg:Hide()
        f.pack:SetTexture(MEDIA .. PACK_FILE[PACK_KINDS[s.pack]])
        f.pack:Show()
    else
        f.pack:Hide()
        f.icon:SetTexture(ICON .. s.icon)
        f.icon:Show()
        f.iconBg:Show()
    end
    sizeSymbol(f, 1)
end

-- un rouleau : 4 cases sur une bande ; pos (en cases) : la case du bas est
-- strip[floor(pos)], la ligne de gain la suivante ; pos croit = la bande
-- descend
local function placeReel(reel, speed)
    local base = math.floor(reel.pos)
    local frac = reel.pos - base
    local a = 1 - 0.45 * math.min(1, (speed or 0) / 25)    -- flou de vitesse
    for r = 0, 3 do
        local cell = reel.cells[r + 1]
        local key = reel.strip[base + r]
        paintSymbol(cell, key)
        cell:ClearAllPoints()
        cell:SetPoint("BOTTOM", reel.frame, "BOTTOM", 0, (r - frac) * CELL)
        cell:SetAlpha(a)
    end
end

-- rouleaux au repos : le dernier resultat (ou des symboles au hasard)
local function idleReels()
    local s = slotsDB()
    local last = s and (s.pending or s.last)
    for i, reel in ipairs(reels) do
        local mid = last and type(last.r) == "table" and SYM[last.r[i]] and last.r[i] or rollSymbol()
        reel.strip = { rollSymbol(), mid, rollSymbol(), rollSymbol() }
        reel.pos = 1
        reel.from, reel.to = 1, 1
        placeReel(reel, 0)
    end
end

local refreshSlots

local function setResult(title, rgb, sub)
    page.result:SetText(title or "")
    rgb = rgb or C.text
    page.result:SetTextColor(rgb[1], rgb[2], rgb[3])
    page.resultSub:SetText(sub or "")
end

-- texte du repos : de quoi jouer, ou ce qu il manque
local function idleText()
    local s = slotsDB()
    local bet = s and s.bet or P.SLOT_BETS[1]
    if (P.db and P.db.shards or 0) < bet then
        setResult(string.format(L.PEDO_SLOT_POOR, bet), { 0.6, 0.6, 0.6 })
    else
        setResult(L.PEDO_SLOT_IDLE, C.text)
    end
end

---------------------------------------------------------------------------
-- Effets du gain : ligne qui clignote, symboles qui battent, etincelles,
-- booster gagne en grand sur des rayons, la machine qui tremble
---------------------------------------------------------------------------

local function clearFx()
    fx = nil
    page.fxLayer:Hide()
    page.prize:Hide()
    page.rays:Hide()
    for _, t in ipairs(page.sparks) do t:Hide() end
    for _, e in ipairs(page.line) do e:SetAlpha(0.55) end
    for _, reel in ipairs(reels) do
        for _, cell in ipairs(reel.cells) do sizeSymbol(cell, 1) end
    end
    page.cabinet:ClearAllPoints()
    page.cabinet:SetPoint("TOPLEFT", page, "TOPLEFT", page.cabX, page.cabY)
    page.open:Hide()
end

-- cases gagnantes : la ligne de gain des rouleaux concernes
local function winningCells(res)
    local out = {}
    for i, reel in ipairs(reels) do
        if res.line ~= "shard2" or res.r[i] == "shard" then out[#out + 1] = reel.cells[2] end
    end
    return out
end

local function startFx(res)
    local now = GetTime()
    if not res.line then
        setResult(L.PEDO_SLOT_LOSE, { 0.6, 0.6, 0.6 })
        return
    end
    fx = { t0 = now, res = res, cells = winningCells(res), shake = 0 }
    local rgb = { C.gold[1], C.gold[2], C.gold[3] }
    if res.kind then
        rgb = PACK_RGB[res.kind]
        local name = packName(res.kind)
        setResult(res.packs > 1 and string.format(L.PEDO_SLOT_PACKS, name, res.packs) or string.format(L.PEDO_SLOT_PACK, name), rgb)
        page.prize.tex:SetTexture(MEDIA .. PACK_FILE[res.kind])
        page.prize.count:SetText(res.packs > 1 and ("x" .. res.packs) or "")
        page.prize:SetAlpha(0)
        page.prize:Show()
        page.rays:SetVertexColor(rgb[1], rgb[2], rgb[3])
        page.rays:Show()
        page.open:Show()
        P.Sound("f_carillon")
        if res.kind == "legendary" then
            kit("UI_LEGENDARY_LOOT_TOAST")
            fx.shake = 0.6
        elseif res.kind == "epic" then
            kit("UI_EPICLOOT_TOAST")
            fx.shake = 0.35
        else
            kit("UI_RAID_LOOT_TOAST_LESSER_ITEM_WON")
        end
    else
        setResult(string.format(L.PEDO_SLOT_WIN, res.shards), rgb, res.line == "shard2" and L.PEDO_SLOT_REFUND or nil)
        kit("TRADING_POST_UI_COLLECTING_COINS")
        if res.line ~= "shard2" then P.Sound("coin") end
    end
    -- etincelles : depuis la ligne de gain, vers le haut, retombent
    local n = res.kind and SPARKS or (res.line == "shard2" and 8 or 16)
    for i, t in ipairs(page.sparks) do
        if i <= n then
            local ang = math.rad(25 + math.random() * 130)
            local v = 140 + math.random() * 220
            t.vx, t.vy = math.cos(ang) * v, math.sin(ang) * v
            t.x0 = (math.random() - 0.5) * (3 * REEL_W)
            t.size = 10 + math.random() * 16
            t.spin = (math.random() - 0.5) * 8
            t:SetVertexColor(rgb[1], rgb[2], rgb[3])
            t:Show()
        else
            t:Hide()
        end
    end
    page.fxLayer:Show()
    page.driver:Show()
end

local function updateFx(now)
    local age = now - fx.t0
    local res = fx.res
    -- ligne de gain et symboles gagnants qui battent
    local beat = math.abs(math.sin(age * 7))
    for _, e in ipairs(page.line) do e:SetAlpha(0.45 + 0.55 * beat) end
    local k = age < 1.6 and (1 + 0.14 * beat * (1 - age / 1.6)) or 1
    for _, cell in ipairs(fx.cells) do sizeSymbol(cell, k) end
    -- etincelles
    local cx, cy = page.window:GetWidth() / 2, page.window:GetHeight() / 2
    for _, t in ipairs(page.sparks) do
        if t:IsShown() then
            local life = 1.3
            if age > life then
                t:Hide()
            else
                local x = t.x0 + t.vx * age
                local y = t.vy * age - 380 * age * age
                t:ClearAllPoints()
                t:SetPoint("CENTER", page.window, "BOTTOMLEFT", cx + x, cy + y)
                t:SetSize(t.size, t.size)
                t:SetAlpha(1 - age / life)
                pcall(t.SetRotation, t, age * t.spin)
            end
        end
    end
    -- booster gagne : surgit sur ses rayons, puis s efface sur les rouleaux
    if res.kind then
        local kk = math.min(1, age / 0.5)
        page.prize:SetScale(math.max(0.05, 0.4 + 0.6 * easeOutBack(kk)))
        local a = age < 0.25 and age / 0.25 or (age > FX_TIME - 0.5 and math.max(0, (FX_TIME - age) / 0.5) or 1)
        page.prize:SetAlpha(a)
        page.rays:SetAlpha(0.75 * a)
        pcall(page.rays.SetRotation, page.rays, age * 0.5)
        page.prize.glow:SetAlpha(0.5 + 0.5 * beat)
    end
    -- la machine tremble (epique, legendaire)
    if fx.shake > 0 and age < fx.shake then
        local amp = 4 * (1 - age / fx.shake)
        page.cabinet:ClearAllPoints()
        page.cabinet:SetPoint("TOPLEFT", page, "TOPLEFT", page.cabX + (math.random() - 0.5) * 2 * amp,
            page.cabY + (math.random() - 0.5) * 2 * amp)
    elseif fx.shake > 0 then
        fx.shake = 0
        page.cabinet:ClearAllPoints()
        page.cabinet:SetPoint("TOPLEFT", page, "TOPLEFT", page.cabX, page.cabY)
    end
    if age > FX_TIME then
        page.prize:Hide()
        page.rays:Hide()
        for _, cell in ipairs(fx.cells) do sizeSymbol(cell, 1) end
        for _, e in ipairs(page.line) do e:SetAlpha(0.55) end
        fx = nil
    end
end

---------------------------------------------------------------------------
-- Tour : bandes, arrets, versement
---------------------------------------------------------------------------

local function ease(x) return 1 - (1 - x) ^ 3 end

local function onLand(i)
    if spin.skipped and i < 3 then return end
    kit("PUT_DOWN_SMALL_CHAIN")
    -- deux boosters sur les deux premiers : suspense sur le troisieme
    if i == 2 and spin.tease then
        P.Sound("f_tambour")
        page.tease:Show()
    end
end

local function finishSpin()
    local res = spin.res
    spin = nil
    page.tease:Hide()
    P.SlotSettle()
    startFx(res)
    refreshSlots()
end

local function updateSpin(now, elapsed)
    local t = now - spin.t0
    local done = true
    for i, reel in ipairs(reels) do
        local D = spin.stop[i]
        local pos
        if t < WIND then
            pos = reel.from - 0.22 * math.sin(math.pi * t / WIND)
        elseif t < D then
            pos = reel.from + (reel.to - reel.from) * ease((t - WIND) / (D - WIND))
        else
            if not spin.landed[i] then
                spin.landed[i] = true
                onLand(i)
            end
            local u = (t - D) / BOUNCE
            pos = u < 1 and (reel.to + 0.16 * math.sin(math.pi * u) * (1 - u)) or reel.to
        end
        if t < D + BOUNCE then done = false end
        local speed = math.abs(pos - reel.pos) / math.max(elapsed or 0.016, 0.001)
        reel.pos = pos
        placeReel(reel, speed)
    end
    if spin.tease and spin.landed[2] and not spin.landed[3] then
        page.tease:SetAlpha(0.35 + 0.45 * math.abs(math.sin(t * 6)))
    else
        page.tease:Hide()
    end
    if done then finishSpin() end
end

local function startSpin()
    if spin or not page then return end
    local s = slotsDB()
    local res = s and P.SlotSpin(s.bet)
    if not res then
        idleText()
        refreshSlots()
        return
    end
    clearFx()
    spin = { res = res, t0 = GetTime(), stop = {}, landed = {} }
    spin.tease = SYM[res.r[1]].pack and SYM[res.r[2]].pack and true or false
    for i, reel in ipairs(reels) do
        local stopAt = (i == 3 and spin.tease) and TEASE_AT or STOP_AT[i]
        spin.stop[i] = stopAt
        -- bande : un symbole sous la vue (l elan), les 4 montres, des
        -- symboles au hasard, puis dessous, la ligne de gain, dessus, cache
        local base = math.floor(reel.pos + 0.5)
        local strip = { rollSymbol() }
        for r = 0, 3 do strip[#strip + 1] = reel.strip[base + r] or rollSymbol() end
        for _ = 1, math.floor(stopAt * SPIN_SPEED) do strip[#strip + 1] = rollSymbol() end
        strip[#strip + 1] = rollSymbol()
        strip[#strip + 1] = res.r[i]
        strip[#strip + 1] = rollSymbol()
        strip[#strip + 1] = rollSymbol()
        reel.strip = strip
        reel.from, reel.to, reel.pos = 2, #strip - 3, 2
    end
    setResult("", nil, nil)
    P.Sound("coin")
    kit("UI_BONUS_LOOT_ROLL_START")
    page.driver:Show()
    refreshSlots()
end

-- clic sur les rouleaux : tout s arrete (le rebond reste)
local function skipSpin()
    if not spin then return end
    local last = math.max(spin.stop[1], spin.stop[2], spin.stop[3])
    local now = GetTime()
    if now - spin.t0 >= last then return end
    spin.skipped = true
    for i = 1, 3 do spin.stop[i] = math.min(spin.stop[i], now - spin.t0 + 0.05) end
end

-- onglet quitte (ou fenetre fermee) : le tour se termine sans animation
function P.SlotsHidden()
    if spin then
        for _, reel in ipairs(reels) do
            reel.pos = reel.to
            reel.from = reel.to
            placeReel(reel, 0)
        end
        spin = nil
        if page then page.tease:Hide() end
    end
    P.SlotSettle()
    if page then clearFx() end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function paintBet(b)
    local s = slotsDB()
    local on = s and s.bet == b.bet
    local c = on and C.gold or C.border
    b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
end

local function buildCabinet(p)
    local W = 3 * REEL_W + 2 * REEL_GAP
    local m = CreateFrame("Button", nil, p)
    p.cabX, p.cabY = 40, -12
    m:SetSize(W + 120, 540)
    m:SetPoint("TOPLEFT", p, "TOPLEFT", p.cabX, p.cabY)
    m:SetScript("OnClick", skipSpin)
    ns.UI.Skin(m, 0.6)
    p.cabinet = m
    local title = m:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 22)
    title:SetPoint("TOP", m, "TOP", 0, -6)
    title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    title:SetText(L.PEDO_SLOT_TITLE)
    -- fenetre des rouleaux
    local w = CreateFrame("Frame", nil, m)
    w:SetSize(W + 16, 3 * CELL + 16)
    w:SetPoint("TOP", m, "TOP", 0, -44)
    ns.UI.Skin(w, 0.97, true)
    w.cuiBorder:SetColorTexture(C.gold[1] * 0.6, C.gold[2] * 0.6, C.gold[3] * 0.6, 1)
    p.window = w
    reels = {}
    for i = 1, 3 do
        local f = CreateFrame("Frame", nil, w)
        f:SetSize(REEL_W, 3 * CELL)
        f:SetPoint("TOPLEFT", w, "TOPLEFT", 8 + (i - 1) * (REEL_W + REEL_GAP), -8)
        pcall(f.SetClipsChildren, f, true)
        -- fond bombe : clair au milieu, sombre en haut et en bas
        local top = f:CreateTexture(nil, "BACKGROUND")
        top:SetPoint("TOPLEFT")
        top:SetPoint("TOPRIGHT")
        top:SetHeight(1.5 * CELL)
        gradient(top, { 0.06, 0.06, 0.08, 1 }, { 0.2, 0.19, 0.24, 1 })
        local bottom = f:CreateTexture(nil, "BACKGROUND")
        bottom:SetPoint("BOTTOMLEFT")
        bottom:SetPoint("BOTTOMRIGHT")
        bottom:SetHeight(1.5 * CELL)
        gradient(bottom, { 0.2, 0.19, 0.24, 1 }, { 0.06, 0.06, 0.08, 1 })
        local reel = { frame = f, cells = {}, strip = {}, pos = 1 }
        for r = 1, 4 do
            local cell = newSymbol(f, ICON_SIZE, PACK_H)
            cell:SetSize(REEL_W, CELL)
            reel.cells[r] = cell
        end
        -- ombre du haut et du bas, par-dessus les cases
        local shade = CreateFrame("Frame", nil, f)
        shade:SetAllPoints()
        shade:SetFrameLevel(f:GetFrameLevel() + 6)
        local st = shade:CreateTexture(nil, "OVERLAY")
        st:SetPoint("TOPLEFT")
        st:SetPoint("TOPRIGHT")
        st:SetHeight(CELL * 0.9)
        gradient(st, { 0, 0, 0, 0.85 }, { 0, 0, 0, 0 })
        local sb = shade:CreateTexture(nil, "OVERLAY")
        sb:SetPoint("BOTTOMLEFT")
        sb:SetPoint("BOTTOMRIGHT")
        sb:SetHeight(CELL * 0.9)
        gradient(sb, { 0, 0, 0, 0 }, { 0, 0, 0, 0.85 })
        reels[i] = reel
    end
    -- lueur sur le fond du 3e rouleau, sous ses cases (suspense)
    p.tease = reels[3].frame:CreateTexture(nil, "BORDER")
    p.tease:SetTexture(MEDIA .. "lueur")
    p.tease:SetBlendMode("ADD")
    p.tease:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    p.tease:SetAllPoints()
    p.tease:Hide()
    -- ligne de gain : cadre d or autour de la rangee du milieu
    local line = CreateFrame("Frame", nil, w)
    line:SetPoint("TOPLEFT", w, "TOPLEFT", 4, -8 - CELL)
    line:SetPoint("BOTTOMRIGHT", w, "TOPRIGHT", -4, -8 - 2 * CELL)
    line:SetFrameLevel(w:GetFrameLevel() + 12)
    p.line = outline(line, "OVERLAY", C.gold[1], C.gold[2], C.gold[3], 1, 2)
    for _, e in ipairs(p.line) do e:SetAlpha(0.55) end
    -- effets (au-dessus des rouleaux)
    local fl = CreateFrame("Frame", nil, m)
    fl:SetAllPoints(m)
    fl:SetFrameLevel(w:GetFrameLevel() + 20)
    fl:Hide()
    p.fxLayer = fl
    p.rays = fl:CreateTexture(nil, "BACKGROUND")
    p.rays:SetTexture(MEDIA .. "rayons")
    p.rays:SetBlendMode("ADD")
    p.rays:SetSize(460, 460)
    p.rays:SetPoint("CENTER", w, "CENTER")
    p.rays:Hide()
    local prize = CreateFrame("Frame", nil, fl)
    prize:SetSize(100, math.floor(100 * PACK_RATIO + 0.5))
    prize:SetPoint("CENTER", w, "CENTER")
    prize.glow = prize:CreateTexture(nil, "BACKGROUND")
    prize.glow:SetTexture(MEDIA .. "lueur")
    prize.glow:SetBlendMode("ADD")
    prize.glow:SetPoint("CENTER")
    prize.glow:SetSize(230, 270)
    prize.tex = prize:CreateTexture(nil, "ARTWORK")
    prize.tex:SetAllPoints()
    prize.tex:SetTexCoord(0, 1, 0, TEX_PACK)
    prize.count = text(prize, "GameFontNormalHuge", 26, "OUTLINE")
    prize.count:SetPoint("BOTTOMRIGHT", prize, "BOTTOMRIGHT", 14, -6)
    prize:Hide()
    p.prize = prize
    p.sparks = {}
    for i = 1, SPARKS do
        local t = fl:CreateTexture(nil, "OVERLAY")
        t:SetTexture(MEDIA .. "etincelle")
        t:SetBlendMode("ADD")
        t:Hide()
        p.sparks[i] = t
    end
    -- resultat
    p.result = text(m, "GameFontNormalHuge", 24, "OUTLINE")
    p.result:SetPoint("TOP", w, "BOTTOM", 0, -18)
    p.result:SetWidth(W + 100)
    p.resultSub = text(m, "GameFontHighlight")
    p.resultSub:SetPoint("TOP", p.result, "BOTTOM", 0, -6)
    p.resultSub:SetWidth(W + 100)
    p.resultSub:SetTextColor(C.text[1], C.text[2], C.text[3], 0.8)
    p.open = ns.UI.Button(m, L.PEDO_SLOT_OPEN, 200, function() P.ToggleBinder(true, "packs") end)
    p.open:SetPoint("TOP", p.resultSub, "BOTTOM", 0, -10)
    p.open:Hide()
    -- mise et lancer
    p.spinBtn = ns.UI.Button(m, "", 260, startSpin)
    p.spinBtn:SetSize(260, 38)
    p.spinBtn:SetPoint("BOTTOM", m, "BOTTOM", 0, 40)
    p.spinBtn.cuiText:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    font(p.spinBtn.cuiText, 16)
    local betLabel = text(m, "GameFontNormal")
    betLabel:SetText(L.PEDO_SLOT_BET)
    p.bets = {}
    local bw = 56
    local total = #P.SLOT_BETS * bw + (#P.SLOT_BETS - 1) * 6
    for i, v in ipairs(P.SLOT_BETS) do
        local b = ns.UI.Button(m, tostring(v), bw, function()
            local s = slotsDB()
            if not s or spin then return end
            s.bet = v
            refreshSlots()
            if not fx then idleText() end
        end)
        b:SetPoint("BOTTOMLEFT", p.spinBtn, "TOP", -total / 2 + (i - 1) * (bw + 6) + 20, 10)
        b.bet = v
        b:HookScript("OnLeave", paintBet)
        p.bets[i] = b
    end
    betLabel:SetPoint("RIGHT", p.bets[1], "LEFT", -8, 0)
    local skip = text(m, "GameFontDisableSmall")
    skip:SetPoint("BOTTOM", m, "BOTTOM", 0, 16)
    skip:SetText(L.PEDO_SLOT_SKIP)
end

-- une ligne du tableau des gains : trois symboles, un texte
local function payRow(parent, y, keys, label, color)
    for i, key in ipairs(keys) do
        local f = newSymbol(parent, 24, 32)
        f:SetSize(26, 34)
        f:SetPoint("TOPLEFT", parent, "TOPLEFT", 14 + (i - 1) * 28, y)
        if key then paintSymbol(f, key) end
    end
    local fs = text(parent, "GameFontHighlight")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 108, y - 2)
    fs:SetWidth(parent:GetWidth() - 120)
    fs:SetJustifyH("LEFT")
    fs:SetText(label)
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    return fs
end

local function buildPaytable(p)
    local t = CreateFrame("Frame", nil, p)
    t:SetSize(366, 470)
    t:SetPoint("TOPRIGHT", p, "TOPRIGHT", -20, -12)
    ns.UI.Skin(t, 0.6)
    local head = t:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(head, 16)
    head:SetPoint("TOPLEFT", t, "TOPLEFT", 14, -12)
    head:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    head:SetText(L.PEDO_SLOT_PAY)
    -- trois boosters : la regle, puis chaque couleur et sa chance
    local rule = payRow(t, -42, { "normal", "rare", "epic" }, L.PEDO_SLOT_P_PACKS)
    rule:SetSpacing(2)
    local y = -104
    for _, kind in ipairs(PACK_KINDS) do
        local f = newSymbol(t, 24, 32)
        f:SetSize(26, 34)
        f:SetPoint("TOPLEFT", t, "TOPLEFT", 70, y + 4)
        paintSymbol(f, kind)
        local fs = text(t, "GameFontHighlight")
        fs:SetPoint("TOPLEFT", t, "TOPLEFT", 108, y - 6)
        local rgb = PACK_RGB[kind]
        fs:SetText(packName(kind))
        fs:SetTextColor(rgb[1], rgb[2], rgb[3])
        local odds = text(t, "GameFontDisableSmall")
        odds:SetPoint("TOPRIGHT", t, "TOPRIGHT", -14, y - 7)
        local n = P.SlotOdds(kind)
        odds:SetText(n and ("1 / " .. n) or "")
        y = y - 36
    end
    y = y - 12
    payRow(t, y, { "shard", "shard", "shard" }, string.format(L.PEDO_SLOT_P_TIMES, P.SLOT_PAY.shard3), C.gold)
    y = y - 44
    payRow(t, y, { "boots", "boots", "boots" }, string.format(L.PEDO_SLOT_P_TIMES, P.SLOT_PAY.boots3), C.gold)
    y = y - 44
    payRow(t, y, { "shard", "shard" }, L.PEDO_SLOT_P_BACK)
    y = y - 50
    local mult = text(t, "GameFontHighlightSmall")
    mult:SetPoint("TOPLEFT", t, "TOPLEFT", 14, y)
    mult:SetWidth(338)
    mult:SetJustifyH("LEFT")
    mult:SetText(L.PEDO_SLOT_P_MULT)
    p.stats = text(t, "GameFontDisableSmall")
    p.stats:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 14, 12)
    p.stats:SetWidth(338)
    p.stats:SetJustifyH("LEFT")
end

function P.BuildSlots(p)
    page = p
    buildCabinet(p)
    buildPaytable(p)
    local driver = CreateFrame("Frame", nil, p)
    driver:Hide()
    driver:SetScript("OnUpdate", function(self, elapsed)
        local now = GetTime()
        if spin then updateSpin(now, elapsed) end
        if fx then updateFx(now) end
        if not spin and not fx then self:Hide() end
    end)
    p.driver = driver
    -- onglet quitte, fenetre fermee : gain verse, effets coupes
    p:HookScript("OnHide", P.SlotsHidden)
    p:HookScript("OnShow", function()
        if not spin then
            idleReels()
            idleText()
        end
    end)
    idleReels()
    idleText()
end

refreshSlots = function()
    if not page then return end
    local s = slotsDB()
    if not s then return end
    for _, b in ipairs(page.bets) do
        paintBet(b)
        b:SetEnabled(not spin)
    end
    page.spinBtn:SetText(string.format(L.PEDO_SLOT_SPIN, s.bet))
    page.spinBtn:SetEnabled(not spin and (P.db.shards or 0) >= s.bet)
    page.stats:SetText(string.format(L.PEDO_SLOT_STATS, s.spins, s.spent, s.won, P.SlotPacksWon()))
end
P.RefreshSlots = function() refreshSlots() end

-- banc d essai
P._slots = { roll = rollSymbol, skip = skipSpin, start = startSpin,
             state = function() return spin, fx, reels end }
