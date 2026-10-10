--[[--------------------------------------------------------------------------
    CorpUI - module Encheres : envoi du courrier (sujet, routines)

      - Sujet rempli tout seul : une somme tapee dans le montant a envoyer
        (mode Envoyer de l argent) devient le sujet ("12po 50pa") si le
        sujet est vide, ou s il est encore celui que CorpUI y avait mis ;
        jamais pendant que le joueur ecrit le sujet.
      - Routines : un nom, un destinataire et des filtres (composants
        d enchantement, objets lies quand equipes a partir d une qualite,
        categories d objets). Leur bouton, dans le volet a droite de
        l onglet Envoyer, remplit le destinataire et le sujet, et joint les
        objets des sacs qui correspondent (12 au plus, comme le jeu). Le
        clic sur "Envoyer" reste celui de Blizzard ; apres l envoi, le
        courrier suivant est prepare (option) tant qu il reste des objets.
        Jamais d objet lie, verrouille, ni d envoi a soi-meme.
    Champs de Blizzard : texte du destinataire et du sujet (SetText),
    pieces jointes par le curseur (PickupContainerItem +
    ClickSendMailItemButton). Aucun crochet, aucun champ Lua ecrit.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local C = ns.COLORS
local AH = ns.AH

local issecret = issecretvalue or function() return false end
local num, str, call, field = AH.num, AH.str, AH.call, AH.field

local W = 240
local PAD = 8
local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12
local STEP = 0.12             -- entre deux pieces jointes

local function opts()
    local db = AH.DB()
    if not db then return nil end
    if type(db.mail) ~= "table" then db.mail = {} end
    local o = db.mail
    if o.autoSubject == nil then o.autoSubject = true end
    if o.chain == nil then o.chain = true end
    if type(o.routines) ~= "table" then o.routines = {} end
    return o
end
AH.MailOpts = opts

local function sendShown()
    return AH.visible(_G.SendMailFrame) and AH.visible(_G.MailFrame)
end

local function plainMoney(c)
    local t = AH.Money(c)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return t
end

local function editText(box)
    if type(box) ~= "table" or not box.GetText then return nil end
    local ok, t = pcall(box.GetText, box)
    return ok and str(t) or nil
end

local function setText(box, t)
    if type(box) == "table" and box.SetText then pcall(box.SetText, box, t) end
end

local function hasFocus(box)
    if type(box) ~= "table" or not box.HasFocus then return false end
    local ok, f = pcall(box.HasFocus, box)
    return ok and f == true
end

---------------------------------------------------------------------------
-- Sujet = montant envoye
---------------------------------------------------------------------------

local lastAuto            -- dernier sujet mis par CorpUI

-- montant tape dans le champ de Blizzard (cuivre)
local function typedMoney()
    local m = _G.SendMailMoney
    if type(m) ~= "table" then return 0 end
    local total = 0
    for key, mult in pairs({ gold = 10000, silver = 100, copper = 1 }) do
        local b = field(m, key)
        if type(b) == "table" and b.GetNumber then
            local ok, v = pcall(b.GetNumber, b)
            v = ok and num(v)
            if v then total = total + v * mult end
        end
    end
    return total
end

local function sendingMoney()
    local b = _G.SendMailSendMoneyButton
    if type(b) ~= "table" or not b.GetChecked then return true end
    local ok, c = pcall(b.GetChecked, b)
    return not ok or c == true
end

local function autoSubject()
    local o = opts()
    if not (o and o.autoSubject) then return end
    local box = _G.SendMailSubjectEditBox
    if hasFocus(box) then return end
    local cur = editText(box) or ""
    local amount = sendingMoney() and typedMoney() or 0
    if amount > 0 then
        local want = plainMoney(amount)
        if (cur == "" or cur == lastAuto) and cur ~= want then
            setText(box, want)
            lastAuto = want
        end
    elseif lastAuto and cur == lastAuto then
        setText(box, "")
        lastAuto = nil
    end
end

---------------------------------------------------------------------------
-- Routines
---------------------------------------------------------------------------

local function itemClass(id)
    if AH.ItemClass then return AH.ItemClass(id) end
end

local function bindType(id)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(info) ~= "function" then return nil end
    local ok, v = pcall(function() return select(14, info(id)) end)
    return ok and num(v) or nil
end

-- une case des sacs correspond-elle a la routine ?
local function matches(r, info)
    if type(info) ~= "table" then return false end
    local id = num(info.itemID)
    if not id or info.isBound == true or info.isLocked == true then return false end
    local classID, subID = itemClass(id)
    if r.ench and ((AH.DEMats and AH.DEMats[id]) or (classID == 7 and subID == 12)) then return true end
    if r.boe and (classID == 2 or classID == 4) and (num(info.quality) or 0) >= (r.minQ or 2) and bindType(id) == 2 then
        return true
    end
    if type(r.cats) == "table" and classID then
        if r.cats[classID .. ":"] or (subID and r.cats[classID .. ":" .. subID]) then return true end
    end
    return false
end

-- cases des sacs qui correspondent : { { bag, slot, id, n } }
local function matchingSlots(r)
    local out = {}
    if not (C_Container and C_Container.GetContainerItemInfo) then return out end
    for _, bag in ipairs(ns.PlayerBags()) do
        for slot = 1, ns.BagSlots(bag) do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and matches(r, info) then out[#out + 1] = { bag = bag, slot = slot, id = info.itemID, n = num(info.stackCount) or 1 } end
        end
    end
    return out
end
AH.RoutineSlots = matchingSlots

local function freeAttachSlots()
    local n = 0
    for i = 1, MAX_ATTACH do
        if not call(HasSendMailItem, i) then n = n + 1 end
    end
    return n
end

local function isMe(name)
    local me = str(call(UnitName, "player"))
    if not (me and name) then return false end
    local n = strlower(strtrim(name))
    return n == strlower(me) or n:match("^([^%-]+)") == strlower(me)
end

local job                  -- pieces jointes en cours { r, queue, i, next, done }
local active               -- derniere routine lancee (pour enchainer)
local status = ""

local function cursorItem()
    local ok, kind = pcall(GetCursorInfo)
    return ok and kind == "item"
end

local function prepare(r)
    if not sendShown() then return end
    if InCombatLockdown() then ns.Say(L.COMBAT_BLOCKED) return end
    local to = r and strtrim(r.to or "") or ""
    if to == "" then ns.Say(L.ROUT_NO_TO) return end
    if isMe(to) then ns.Say(L.ROUT_SELF) return end
    local slots = matchingSlots(r)
    if #slots == 0 then
        status = string.format(L.ROUT_NOTHING, r.name or "?")
        active = nil
        return
    end
    setText(_G.SendMailNameEditBox, to)
    local subject = editText(_G.SendMailSubjectEditBox) or ""
    if subject == "" or subject == lastAuto then
        setText(_G.SendMailSubjectEditBox, r.name or to)
        lastAuto = nil
    end
    local free = freeAttachSlots()
    local queue = {}
    for i = 1, math.min(free, #slots) do queue[i] = slots[i] end
    job = { r = r, queue = queue, i = 1, next = 0, left = #slots - #queue }
    active = r
    status = string.format(L.ROUT_ATTACHING, #queue)
end
AH.RoutinePrepare = prepare

local function stepJob()
    if not job then return end
    if not sendShown() or InCombatLockdown() then job = nil return end
    local now = GetTime()
    if now < job.next then return end
    local e = job.queue[job.i]
    if not e then
        status = string.format(L.ROUT_READY, #job.queue, job.r.to or "?") ..
            (job.left > 0 and ("  " .. string.format(L.ROUT_LEFT, job.left)) or "")
        job = nil
        return
    end
    if cursorItem() then call(ClearCursor) end
    local fn = C_Container and C_Container.PickupContainerItem or PickupContainerItem
    pcall(fn, e.bag, e.slot)
    if cursorItem() then
        pcall(ClickSendMailItemButton)
        -- refuse (objet non envoyable) : on le repose
        if cursorItem() then call(ClearCursor) end
    end
    job.i = job.i + 1
    job.next = now + STEP
end

---------------------------------------------------------------------------
-- Volet (onglet Envoyer)
---------------------------------------------------------------------------

local side

local function routineLabel(r)
    local n = 0
    for _, s in ipairs(matchingSlots(r)) do n = n + 1 end
    return string.format(L.ROUT_BUTTON, r.name or "?", r.to ~= "" and r.to or "?", n), n
end

local function buildSide()
    side = CreateFrame("Frame", "CorpUIMailSendSide", UIParent)
    side:SetSize(W, 300)
    side:EnableMouse(true)
    ns.UI.Skin(side, 0.96, true)
    local title = side:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(title, 14)
    title:SetPoint("TOPLEFT", side, "TOPLEFT", PAD, -8)
    title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    title:SetText(L.ROUT_TITLE)
    side.auto = ns.UI.Check(side, L.ROUT_AUTO_SUBJECT, function(v) local o = opts() if o then o.autoSubject = v end end)
    side.auto:SetPoint("TOPLEFT", side, "TOPLEFT", PAD - 4, -30)
    AH.Header(side, L.ROUT_SEC, -60)
    side.buttons = {}
    side.empty = AH.Text(side, "GameFontDisableSmall", "LEFT")
    side.empty:SetPoint("TOPLEFT", side, "TOPLEFT", PAD, -84)
    side.empty:SetPoint("RIGHT", side, "RIGHT", -PAD, 0)
    side.empty:SetHeight(40)
    side.empty:SetWordWrap(true)
    side.empty:SetJustifyV("TOP")
    side.empty:SetText(L.ROUT_NONE)
    side.status = AH.Text(side, "GameFontHighlightSmall", "LEFT")
    side.status:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", PAD, 40)
    side.status:SetPoint("RIGHT", side, "RIGHT", -PAD, 0)
    side.status:SetHeight(28)
    side.status:SetWordWrap(true)
    side.status:SetJustifyV("BOTTOM")
    local manage = ns.UI.Button(side, L.ROUT_MANAGE, W - PAD * 2, function()
        if ns.ShowPanel and _G.CorpUIAuctionOptions then ns.ShowPanel(_G.CorpUIAuctionOptions)
        elseif SlashCmdList and SlashCmdList.CORPUI then SlashCmdList.CORPUI("hv") end
    end)
    manage:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", PAD, PAD)
    side:Hide()
end

local function paint()
    local o = opts()
    side.auto:SetChecked(o and o.autoSubject or false)
    local routines = o and o.routines or {}
    for i, r in ipairs(routines) do
        local b = side.buttons[i]
        if not b then
            b = ns.UI.Button(side, "", W - PAD * 2, function(self) if self.r then prepare(self.r) end end)
            b:SetPoint("TOPLEFT", side, "TOPLEFT", PAD, -84 - (i - 1) * 26)
            b.cuiText:SetWordWrap(false)
            b.cuiText:SetWidth(W - PAD * 2 - 12)
            side.buttons[i] = b
        end
        b.r = r
        local label, n = routineLabel(r)
        b:SetText(label)
        b:SetEnabled(n > 0 and not job)
        b:Show()
    end
    for i = #routines + 1, #side.buttons do side.buttons[i]:Hide() end
    side.empty:SetShown(#routines == 0)
    side.status:SetText(status)
end

local acc, paintAcc = 0, 0
local function tick(dt)
    local o = opts()
    if not (o and sendShown()) then
        if side and side:IsShown() then side:Hide() end
        job = nil
        return
    end
    autoSubject()
    stepJob()
    if not side then buildSide() end
    local mf = _G.MailFrame
    if side.anchoredTo ~= mf then
        side:ClearAllPoints()
        side:SetPoint("TOPLEFT", mf, "TOPRIGHT", 4, 0)
        side.anchoredTo = mf
    end
    local okH, h = pcall(mf.GetHeight, mf)
    h = okH and num(h)
    if h and h > 200 and math.abs((side:GetHeight() or 0) - h) > 0.5 then side:SetHeight(h) end
    if ns.AHFollow then ns.AHFollow(side, mf) end
    if not side:IsShown() then
        side:Show()
        paintAcc = 1
    end
    paintAcc = paintAcc + dt
    if paintAcc >= 0.5 then
        paintAcc = 0
        paint()
    end
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.05 then return end
    tick(acc)
    acc = 0
end)
driver:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("hv", driver) then return end
    if event == "MAIL_SEND_SUCCESS" then
        lastAuto = nil
        local o = opts()
        local r = active
        if r and o and o.chain then
            -- Blizzard vide le formulaire apres l envoi : courrier suivant
            C_Timer.After(0.6, function()
                if sendShown() and #matchingSlots(r) > 0 then prepare(r)
                else
                    status = string.format(L.ROUT_DONE, r.name or "?")
                    active = nil
                end
            end)
        else
            status = ""
        end
    elseif event == "MAIL_CLOSED" then
        job, active, status, lastAuto = nil, nil, "", nil
    end
end)
for _, e in ipairs({ "MAIL_SEND_SUCCESS", "MAIL_CLOSED" }) do pcall(driver.RegisterEvent, driver, e) end

---------------------------------------------------------------------------
-- Reglages des routines (panneau /corp hv)
---------------------------------------------------------------------------

local QUALITY = { 2, 3, 4 }

ns.AHPanelHooks = ns.AHPanelHooks or {}
table.insert(ns.AHPanelHooks, function(panel, form)
    local cur = 1
    local function R()
        local o = opts()
        local list = o and o.routines or {}
        if not list[cur] then cur = 1 end
        return list[cur]
    end
    form:Header(L.ROUT_SEC_OPTS)
    form:Check(L.ROUT_AUTO_SUBJECT, function() local o = opts() return o and o.autoSubject end, function(v)
        local o = opts()
        if o then o.autoSubject = v end
    end)
    form:Check(L.ROUT_CHAIN, function() local o = opts() return o and o.chain end, function(v)
        local o = opts()
        if o then o.chain = v end
    end)
    local sel = form:Select(nil, function()
        local out = {}
        for i, r in ipairs((opts() or {}).routines or {}) do out[#out + 1] = { value = i, text = r.name or "?" } end
        if #out == 0 then out[1] = { value = 0, text = L.ROUT_NONE_SHORT } end
        return out
    end, function() return R() and cur or 0 end, function(v) if v ~= 0 then cur = v end end, 200)
    local new = ns.UI.Button(panel, L.BUY_NEW, 70, function()
        local o = opts()
        if not o then return end
        table.insert(o.routines, { name = string.format(L.ROUT_NEW_NAME, #o.routines + 1), to = "", ench = false, boe = false, minQ = 2, cats = {} })
        cur = #o.routines
        form.Changed()
    end)
    new:SetPoint("LEFT", sel, "RIGHT", 6, 0)
    local del = ns.UI.Button(panel, L.BUY_DELETE, 70, function(self)
        local o = opts()
        if not (o and R()) then return end
        if not self.armed then
            self.armed = true
            self:SetText(L.AH_SURE)
            C_Timer.After(3, function() if self.armed then self.armed = nil self:SetText(L.BUY_DELETE) end end)
            return
        end
        self.armed = nil
        self:SetText(L.BUY_DELETE)
        table.remove(o.routines, cur)
        cur = 1
        form.Changed()
    end)
    del:SetPoint("LEFT", new, "RIGHT", 4, 0)
    -- nom et destinataire
    local function edit(label, x, key)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + x, form.y)
        fs:SetText(label)
        local e = ns.UI.EditBox(panel, 190, 20)
        e:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + x, form.y - 16)
        local function commit(self)
            local r = R()
            if r then r[key] = strtrim(self:GetText() or "") end
            form:Refresh()
        end
        e:SetScript("OnEnterPressed", function(self) commit(self) self:ClearFocus() end)
        e:HookScript("OnEditFocusLost", commit)
        table.insert(form.refreshers, function()
            local r = R()
            if not e:HasFocus() then e:SetText(r and r[key] or "") end
            e:SetEnabled(r ~= nil)
        end)
        return e
    end
    edit(L.ROUT_NAME, 0, "name")
    edit(L.ROUT_TO, 210, "to")
    form.y = form.y - 44
    form:Columns(2)
    form:Check(L.ROUT_ENCH, function() local r = R() return r and r.ench end, function(v) local r = R() if r then r.ench = v end end)
    form:Check(L.ROUT_BOE, function() local r = R() return r and r.boe end, function(v) local r = R() if r then r.boe = v end end)
    form:EndColumns()
    form:Cycle(L.ROUT_MINQ, QUALITY, { [2] = L.ROUT_Q2, [3] = L.ROUT_Q3, [4] = L.ROUT_Q4 },
        function() local r = R() return r and r.minQ or 2 end, function(v) local r = R() if r then r.minQ = v end end)
    -- categories : la liste ajoute ou retire (coche devant)
    form:Select(L.ROUT_CATS, function()
        local r = R()
        local out = {}
        for _, opt in ipairs(AH.ClassOptions and AH.ClassOptions() or {}) do
            if opt.value ~= "none" then
                local on = r and type(r.cats) == "table" and r.cats[opt.value]
                out[#out + 1] = { value = opt.value, text = (on and "|cff6be070✓|r " or "   ") .. opt.text }
            end
        end
        return out
    end, function() return "" end, function(v)
        local r = R()
        if not r then return end
        if type(r.cats) ~= "table" then r.cats = {} end
        r.cats[v] = not r.cats[v] or nil
    end, 260)
    local catText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    catText:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, form.y + 4)
    catText:SetWidth(form.width - 16)
    catText:SetJustifyH("LEFT")
    form.y = form.y - 18
    table.insert(form.refreshers, function()
        local r = R()
        local names = {}
        local opts2 = AH.ClassOptions and AH.ClassOptions() or {}
        for _, opt in ipairs(opts2) do
            if r and type(r.cats) == "table" and r.cats[opt.value] then names[#names + 1] = opt.text end
        end
        catText:SetText(#names > 0 and table.concat(names, ", ") or L.ROUT_CATS_NONE)
        del:SetEnabled(r ~= nil)
    end)
end)

-- banc d essai
AH._send = { tick = tick, step = stepJob, status = function() return status end, job = function() return job end,
             matches = matches }
