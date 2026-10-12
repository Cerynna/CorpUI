--[[--------------------------------------------------------------------------
    CorpUI - module Suivi de quetes
    Notre liste des quetes suivies, a la place de "Tous les objectifs" de
    Blizzard : titre colore selon la difficulte, objectifs avec progression
    (verts une fois faits), "Prete a rendre" quand la quete est terminee.
    Repliable (bouton du titre), deplacable (poignees communes).

    Clics sur une quete (titre ou objectif), comme le suivi de Blizzard :
    - clic : ouvre le journal sur la quete (deja sur sa fiche : le ferme).
      Quete d une autre zone : Blizzard replie sa categorie a chaque
      ouverture du journal ; le clic deplie alors la categorie (clic sur
      son en-tete), le suivant ouvre la fiche ;
    - Maj + clic (gauche ou droit) : son lien si une saisie l accepte
      (discussion, Communautes, macro), sinon (gauche) ne plus la suivre ;
    - clic droit : menu (mettre en avant, partager, lien, ne plus suivre,
      abandonner avec une confirmation CorpUI, posee a cote de la liste,
      Echap la ferme hors combat).

    Ouvrir le journal depuis le code de l addon le marquerait (taint) : la
    carte du monde garde le mapID ecrit, et son OnShow appelle une fonction
    reservee (PerformEmote) -> "CorpUI a ete bloque" a chaque ouverture.
    Le clic gauche passe donc par un bouton securise (CorpUIQuestsClick),
    pose hors combat sur la quete survolee : c est le code securise qui
    clique sur le bouton L du micro-menu et/ou sur la ligne de la quete
    (ou l en-tete de sa categorie) dans la liste du journal, comme le
    ferait la souris. CorpUI n appelle
    aucune fonction du journal ou de la carte, ne pose aucun hook et ne
    fait que lire leurs champs. En combat ce bouton est range : le clic
    gauche n ouvre rien (message discret), le reste fonctionne.
    Appels directs a l API : arret du suivi, mise en avant (C_SuperTrack),
    partage (QuestLogPushQuest), abandon (C_QuestLog, sans StaticPopup ;
    la "quete a abandonner" du jeu est remise ensuite : la boite d abandon
    de Blizzard, si elle est ouverte, garde sa quete).
    Le suivi de Blizzard est range dans le cadre cache.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local WIDTH, MAX_QUESTS = 230, 15
local BLIZZ = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }
local PICK_NAME = "CorpUIQuestsPick"   -- cible du /click de la macro securisee

local issecret = issecretvalue or function() return false end

local db
local frame, header, body
local lines = {}          -- textes reutilises
local blocks = {}         -- questID -> bloc { id, title, first, y1, y2 }
local pending
local hover, hoverID, tipCombat   -- surbrillance du bloc survole
local click, pick         -- boutons securises (crees hors combat)
local fighting            -- entre PLAYER_REGEN_DISABLED et _ENABLED
local menuQuest, menuOwner, confirm
local lastSay = 0

-- combat : verrouillage en cours, ou annonce (l evenement precede le verrou)
local function combat()
    return fighting or InCombatLockdown()
end

---------------------------------------------------------------------------
-- Donnees
---------------------------------------------------------------------------

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

-- valeur vraie et lisible (jamais de test sur une valeur secrete)
local function yes(v)
    if issecret(v) then return false end
    return v and true or false
end

-- quetes suivies ; si l API de suivi manque, toutes celles du journal
local function watchedQuests()
    local list = {}
    local Q = C_QuestLog
    if not Q then return list end
    local n = safe(Q.GetNumQuestWatches)
    if n and Q.GetQuestIDForQuestWatchIndex then
        for i = 1, n do
            local id = safe(Q.GetQuestIDForQuestWatchIndex, i)
            if not issecret(id) and id then table.insert(list, id) end
        end
    else
        for i = 1, safe(Q.GetNumQuestLogEntries) or 0 do
            local info = safe(Q.GetInfo, i)
            if info and not info.isHeader and info.questID then table.insert(list, info.questID) end
        end
    end
    return list
end

local function questData(id)
    local Q = C_QuestLog
    local idx = safe(Q.GetLogIndexForQuestID, id)
    local info = idx and safe(Q.GetInfo, idx)
    if not info then return nil end
    local complete = safe(Q.IsComplete, id)
    local objectives = safe(Q.GetQuestObjectives, id) or {}
    return {
        id = id,
        title = info.title or "?",
        level = info.level or 0,
        complete = complete and complete ~= 0,
        objectives = objectives,
    }
end

local function levelColor(level)
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, level)
        if ok and c then return c.r, c.g, c.b end
    end
    return 1, 0.82, 0
end

-- texte de Blizzard (deja traduit) s il existe, sinon le notre
local function gstr(name, fallback)
    local v = _G[name]
    if not issecret(v) and type(v) == "string" and v ~= "" then return v end
    return fallback
end

local function questTitle(id)
    local t = safe(C_QuestLog.GetTitleForQuestID, id)
    if issecret(t) or type(t) ~= "string" or t == "" then
        local q = questData(id)
        return q and q.title or "?"
    end
    return t
end

-- un message discret, pas plus d un toutes les 5 s
local function say(msg)
    local now = GetTime()
    if now - lastSay < 5 then return end
    lastSay = now
    ns.Say(msg)
end

---------------------------------------------------------------------------
-- Actions sur une quete (API seulement, aucun code de Blizzard)
---------------------------------------------------------------------------

-- modificateur du clic (Maj par defaut), comme le suivi de Blizzard
local function modified(action)
    if IsModifiedClick then
        local ok, v = pcall(IsModifiedClick, action)
        if ok then return yes(v) end
    end
    return yes(IsShiftKeyDown())
end

-- saisie de discussion ouverte
local function chatWindow()
    local U = ChatFrameUtil
    local w
    if U then w = safe(U.GetActiveWindow) end
    if issecret(w) then return nil end
    if not w then w = safe(ChatEdit_GetActiveWindow) end
    if issecret(w) then return nil end
    return w
end

-- saisie qui a le focus (lecture seule d un cadre de Blizzard)
local function hasFocus(get)
    local ok, v = pcall(function()
        local e = get()
        return e and e:HasFocus()
    end)
    return ok and yes(v)
end

-- une saisie recevrait le lien d une quete : memes cas que
-- ChatFrameUtil.InsertLink (macro, Communautes, discussion)
local function linkTarget()
    if hasFocus(function() return MacroFrameText end) then return true end
    if hasFocus(function() return CommunitiesFrame and CommunitiesFrame.ChatEditBox end) then return true end
    return chatWindow() ~= nil
end

local function insertLink(id)
    if not linkTarget() then return false end
    local link = safe(GetQuestLink, id)
    if issecret(link) or type(link) ~= "string" then return false end
    local U = ChatFrameUtil
    return yes(safe((U and U.InsertLink) or ChatEdit_InsertLink, link))
end

-- zone de depart (NPE) : Blizzard interdit d arreter le suivi
local function canUntrack()
    return not yes(C_PlayerInfo and safe(C_PlayerInfo.IsPlayerNPERestricted))
end

local function untrack(id)
    if canUntrack() then safe(C_QuestLog.RemoveQuestWatch, id) end
end

-- fn executee avec la quete id selectionnee, puis on remet l ancienne
local function withSelected(id, fn)
    local Q = C_QuestLog
    local old = safe(Q.GetSelectedQuest)
    safe(Q.SetSelectedQuest, id)
    local a = fn()
    if not issecret(old) and old then safe(Q.SetSelectedQuest, old) end
    return a
end

local function sound(key)
    local id = SOUNDKIT and SOUNDKIT[key]
    if id then safe(PlaySound, id) end
end

local function canShare(id)
    return yes(safe(IsInGroup)) and yes(safe(C_QuestLog.IsPushableQuest, id))
end

local function share(id)
    local idx = safe(C_QuestLog.GetLogIndexForQuestID, id)
    if issecret(idx) or not idx then return end
    withSelected(id, function() safe(QuestLogPushQuest, idx) end)
    sound("IG_QUEST_LOG_OPEN")
end

-- "quete a abandonner" du jeu (celle de la boite de Blizzard si elle est
-- ouverte : son Oui abandonne la quete de ce reglage, pas un questID)
local function abandonState()
    local cur = safe(C_QuestLog.GetAbandonQuest)
    if issecret(cur) or type(cur) ~= "number" then return nil end
    return cur
end

-- remet la quete a abandonner d avant (si ce n est pas id et qu elle existe)
local function restoreAbandon(prev, id)
    if not prev or prev == 0 or prev == id then return end
    local idx = safe(C_QuestLog.GetLogIndexForQuestID, prev)
    if issecret(idx) or not idx then return end
    withSelected(prev, function() safe(C_QuestLog.SetAbandonQuest) end)
end

-- objets de quete detruits par l abandon (noms)
local function abandonItems(id)
    local Q = C_QuestLog
    local prev = abandonState()
    local items = withSelected(id, function()
        safe(Q.SetAbandonQuest)
        return safe(Q.GetAbandonQuestItems)
    end)
    restoreAbandon(prev, id)
    local names = {}
    if type(items) == "table" then
        for _, itemID in ipairs(items) do
            if not issecret(itemID) then
                table.insert(names, ns.ItemName(itemID) or tostring(itemID))
            end
        end
    end
    return names
end

-- meme suite que la boite de Blizzard, sans StaticPopup
local function doAbandon(id)
    local Q = C_QuestLog
    local prev = abandonState()
    withSelected(id, function() safe(Q.SetAbandonQuest) end)
    if type(Q.GetAbandonQuest) == "function" then
        local cur = safe(Q.GetAbandonQuest)
        if issecret(cur) or cur ~= id then
            restoreAbandon(prev, id)
            return
        end
    end
    safe(Q.AbandonQuest)
    sound("IG_QUEST_LOG_ABANDON_QUEST")
    restoreAbandon(prev, id)
end

---------------------------------------------------------------------------
-- Confirmation d abandon (boite CorpUI)
---------------------------------------------------------------------------

local function buildConfirm()
    local C = ns.COLORS
    confirm = CreateFrame("Frame", "CorpUIQuestsConfirm", UIParent, "BackdropTemplate")
    confirm:SetSize(330, 100)
    -- (posee a cote de la liste a chaque ouverture : pas a la place des
    -- boites de Blizzard, StaticPopup1 est en TOP 0,-135)
    confirm:SetFrameStrata("DIALOG")
    confirm:SetClampedToScreen(true)
    confirm:EnableMouse(true)
    -- Echap ferme la boite (hors combat : la consommer demande
    -- SetPropagateKeyboardInput, interdit en combat) ; le reste va au jeu
    confirm:SetScript("OnKeyDown", function(self, key)
        if issecret(key) or key ~= "ESCAPE" then return end
        if not InCombatLockdown() then pcall(self.SetPropagateKeyboardInput, self, false) end
        self:Hide()
    end)
    ns.UI.SetBackdrop(confirm, 0.98)
    ns.UI.Shadow(confirm)
    confirm.text = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    confirm.text:SetPoint("TOPLEFT", confirm, "TOPLEFT", 14, -16)
    confirm.text:SetPoint("TOPRIGHT", confirm, "TOPRIGHT", -14, -16)
    confirm.text:SetJustifyH("CENTER")
    confirm.text:SetWordWrap(true)
    confirm.text:SetTextColor(C.text[1], C.text[2], C.text[3])
    local ok = ns.UI.Button(confirm, gstr("YES", L.QUESTS_YES), 110, function()
        local id = confirm.questID
        confirm:Hide()
        if id then doAbandon(id) end
    end)
    ok:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -6, 14)
    local no = ns.UI.Button(confirm, gstr("NO", L.QUESTS_NO), 110, function() confirm:Hide() end)
    no:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 6, 14)
    confirm:Hide()
end

-- a cote de la liste, du cote ou il y a de la place
local function placeConfirm()
    confirm:ClearAllPoints()
    local x = frame:GetCenter()
    local right = x and (x * frame:GetEffectiveScale() > UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2)
    if right then
        confirm:SetPoint("TOPRIGHT", frame, "TOPLEFT", -8, 0)
    else
        confirm:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, 0)
    end
end

-- clavier de la boite : seulement si les autres touches passent au jeu
-- (propagation reglable hors combat ; en combat, on garde ce qui est pose)
local function confirmKeys()
    local propagate
    if InCombatLockdown() then
        local ok, v = pcall(confirm.GetPropagateKeyboardInput, confirm)
        propagate = ok and not issecret(v) and v == true
    else
        propagate = pcall(confirm.SetPropagateKeyboardInput, confirm, true)
    end
    pcall(confirm.EnableKeyboard, confirm, propagate and true or false)
end

local function askAbandon(id)
    if not confirm then buildConfirm() end
    local text = string.format(L.QUESTS_ABANDON_ASK, questTitle(id))
    local items = abandonItems(id)
    if #items > 0 then
        text = text .. "\n\n" .. string.format(L.QUESTS_ABANDON_ITEMS, table.concat(items, ", "))
    end
    confirm.questID = id
    confirm.text:SetText(text)
    confirm:SetHeight(math.max(90, (confirm.text:GetStringHeight() or 0) + 66))
    placeConfirm()
    confirmKeys()
    confirm:Show()
end

---------------------------------------------------------------------------
-- Menu du clic droit (menu partage de CorpUI)
---------------------------------------------------------------------------

local function questMenu()
    local id = menuQuest
    local list = { width = 190 }
    -- en-tete : le titre, en or, inerte (ni surbrillance ni clic)
    table.insert(list, { value = "title", text = questTitle(id), title = true })
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        local cur = safe(C_SuperTrack.GetSuperTrackedQuestID)
        if not issecret(cur) and cur == id then
            table.insert(list, { value = "unfocus", text = gstr("STOP_SUPER_TRACK_QUEST", L.QUESTS_MENU_UNFOCUS) })
        else
            table.insert(list, { value = "focus", text = gstr("SUPER_TRACK_QUEST", L.QUESTS_MENU_FOCUS) })
        end
    end
    if canShare(id) and QuestLogPushQuest then
        table.insert(list, { value = "share", text = gstr("SHARE_QUEST", L.QUESTS_MENU_SHARE) })
    end
    if linkTarget() then
        table.insert(list, { value = "link", text = L.QUESTS_MENU_LINK })
    end
    if canUntrack() then
        table.insert(list, { value = "untrack", text = gstr("OBJECTIVES_STOP_TRACKING", L.QUESTS_MENU_UNTRACK) })
    end
    if yes(safe(C_QuestLog.CanAbandonQuest, id)) then
        table.insert(list, { value = "abandon", text = "|cffff6b6b" .. L.QUESTS_MENU_ABANDON .. "|r" })
    end
    return list
end

local function onMenu(v)
    local id = menuQuest
    if issecret(id) or not id then return end
    if v == "focus" then
        safe(C_SuperTrack.SetSuperTrackedQuestID, id)
    elseif v == "unfocus" then
        safe(C_SuperTrack.SetSuperTrackedQuestID, 0)
    elseif v == "share" then
        share(id)
    elseif v == "link" then
        insertLink(id)
    elseif v == "untrack" then
        untrack(id)
    elseif v == "abandon" then
        askAbandon(id)
    end
end

-- le menu partage de CorpUI, s il est ouvert pour une de nos quetes
local function questMenuShown()
    local m = CorpUISelectMenu
    return m and menuOwner and m:IsShown() and m.owner == menuOwner and m or nil
end

local function hideQuestMenu()
    local m = questMenuShown()
    if m then m:Hide() end
end

-- support du menu : un cadre invisible (sans souris) sur tout le bloc. Le
-- menu se ferme a l appui hors de son support : avec le bloc entier, un
-- clic droit sur un objectif le referme au lieu de le rouvrir.
local function placeOwner(blk)
    if not menuOwner then menuOwner = CreateFrame("Frame", nil, body) end
    menuOwner:ClearAllPoints()
    menuOwner:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -blk.y1)
    menuOwner:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT", 0, -blk.y2)
    menuOwner:Show()
    return menuOwner
end

local function openQuestMenu(id, blk, fallback)
    -- ouvert pour une autre quete : on le referme avant (sinon bascule)
    if menuQuest ~= id then hideQuestMenu() end
    menuQuest = id
    ns.HideTooltip()
    local owner = blk and placeOwner(blk) or fallback
    ns.UI.OpenMenu(owner, questMenu, function() return "title" end, onMenu)
end

-- liste mise a jour : le menu suit sa quete, ou se ferme si elle est partie
local function syncMenu()
    if not questMenuShown() then return end
    local blk = menuQuest and blocks[menuQuest]
    if blk then placeOwner(blk) else hideQuestMenu() end
end

---------------------------------------------------------------------------
-- Clic gauche : ouverture du journal par un bouton securise
---------------------------------------------------------------------------

-- bouton L du micro-menu (il bascule le journal), s il existe
local function microButton()
    local ok, f = pcall(function()
        local b = QuestLogMicroButton
        if type(b) == "table" and type(b.Click) == "function" then return b end
    end)
    return ok and f or nil
end

-- journal de quetes visible (liste ou fiche, a cote de la carte)
local function logShown()
    local ok, v = pcall(function() return QuestMapFrame:IsVisible() end)
    return ok and yes(v)
end

-- le journal montre deja la fiche de la quete id (lecture seule)
local function detailsOf(id)
    local ok, v = pcall(function()
        local d = QuestMapFrame.DetailsFrame
        local q = d.questID
        return d:IsVisible() and not issecret(q) and q == id
    end)
    return ok and yes(v)
end

-- ligne de la quete id dans la liste du journal de Blizzard (lecture
-- seule de son groupe de boutons ; il garde ses lignes journal ferme)
local function logLine(id)
    local found
    pcall(function()
        for b in QuestScrollFrame.titleFramePool:EnumerateActive() do
            local q = b.questID
            if not issecret(q) and q == id and type(b.Click) == "function" then
                found = b
                return
            end
        end
    end)
    return found
end

-- en-tete REPLIE de la categorie de la quete id dans la liste du journal
-- (a l ouverture et a chaque changement de carte, Blizzard replie les
-- categories hors de la carte affichee : leurs quetes n ont pas de ligne)
local HEADER_POOLS = { "headerFramePool", "covenantCallingsHeaderFramePool" }
local function logHeader(id)
    local found
    pcall(function()
        local Q = C_QuestLog
        local h = Q.GetHeaderIndexForQuest(id)
        if issecret(h) or type(h) ~= "number" then return end
        local info = Q.GetInfo(h)
        if issecret(info) or type(info) ~= "table" then return end
        local collapsed = info.isCollapsed
        if issecret(collapsed) or not collapsed then return end
        for _, key in ipairs(HEADER_POOLS) do
            local pool = QuestScrollFrame[key]
            if pool then
                for b in pool:EnumerateActive() do
                    local i = b.questLogIndex
                    if not issecret(i) and i == h and type(b.Click) == "function" then
                        found = b
                        return
                    end
                end
            end
        end
    end)
    return found
end

-- Que fait un clic gauche simple sur la quete id (hors combat) ?
--   "close"    journal ouvert sur sa fiche : bouton L (il se ferme)
--   "pick"     journal ouvert : sa ligne dans le journal (Blizzard ouvre
--              la fiche et centre la carte sur sa zone, comme un clic de
--              la souris dans sa liste)
--   "unfold"   journal ouvert, pas de ligne car sa categorie est repliee :
--              l en-tete de la categorie (Blizzard la deplie) ; le clic
--              suivant trouve la ligne et ouvre la fiche
--   "pickopen" journal ferme, ligne connue : macro securisee qui clique
--              sa ligne (fiche preparee) puis le bouton L. A l ouverture,
--              Blizzard centre la carte sur le joueur : il referme la fiche
--              d une quete d une autre zone et replie sa categorie ; on
--              arrive alors sur la liste ("unfold" au clic suivant).
--   "open"     journal ferme : bouton L (la liste)
local function plan(id)
    local micro = microButton()
    if logShown() then
        if detailsOf(id) then
            if micro then return "close", micro end
            return nil
        end
        local b = logLine(id)
        if b then return "pick", b end
        b = logHeader(id)
        if b then return "unfold", b end
        return nil
    end
    if not micro then return nil end
    local b = pick and logLine(id)
    if b then return "pickopen", b end
    return "open", micro
end

-- attributs du bouton securise : hors combat seulement
local function arm(mode, target)
    if not click or InCombatLockdown() then return end
    if mode == "pickopen" then
        pick:SetAttribute("clickbutton", target)
        -- /click part "relache" ; pick agit toujours au relachement
        -- (useOnKeyDown = false), quel que soit ActionButtonUseKeyDown
        click:SetAttribute("type", "macro")
        click:SetAttribute("macrotext", "/click " .. PICK_NAME .. "\n/click QuestLogMicroButton")
    elseif mode then
        click:SetAttribute("type", "click")
        click:SetAttribute("clickbutton", target)
    else
        click:SetAttribute("type", nil)
        pick:SetAttribute("clickbutton", nil)
    end
end

-- que demande ce clic ? "menu", "link", "untrack" ou "open"
-- (meme ordre que Blizzard : le lien d abord, pour les deux boutons)
local function wants(button)
    if button ~= "LeftButton" and button ~= "RightButton" then return nil end
    if modified("CHATLINK") and linkTarget() then return "link" end
    if button == "RightButton" then return "menu" end
    if modified("QUESTWATCHTOGGLE") then return "untrack" end
    return "open"
end

-- suite insecurisee d un clic. mode : ce que le clic securise a fait
-- ("pick", "unfold"...), false si rien (bouton securise sans plan),
-- nil si le clic est arrive sur la ligne (bouton securise range)
local function onQuestClick(want, id, blk, fallback, mode)
    if issecret(id) or not id then return end
    if want ~= "menu" then hideQuestMenu() end
    if want == "menu" then
        openQuestMenu(id, blk, fallback)
    elseif want == "link" then
        if not insertLink(id) and modified("QUESTWATCHTOGGLE") then untrack(id) end
    elseif want == "untrack" then
        untrack(id)
    elseif want == "open" then
        if mode == "unfold" then
            say(L.QUESTS_UNFOLDED)
        elseif mode then
            return
        elseif combat() then
            say(L.QUESTS_COMBAT)
        elseif mode == false and logShown() then
            say(L.QUESTS_NOT_LISTED)
        end
    end
end

-- un clic = appui + relachement ; l action securisee part sur l un des
-- deux (reglage "action a l appui") : le plan est fait a l appui et
-- repris au relachement, les attributs sont remis a zero apres chacun.
local function preClick(self, button, down)
    if down or not self.cuiWant then
        self.cuiWant = wants(button) or "none"
        self.cuiMode, self.cuiTarget = nil, nil
        local id = self.questID
        if self.cuiWant == "open" and not issecret(id) and id and not InCombatLockdown() then
            self.cuiMode, self.cuiTarget = plan(id)
        end
    end
    arm(self.cuiMode, self.cuiTarget)
end

local function postClick(self, button, down)
    arm(nil)
    if down then return end
    local want, mode, blk = self.cuiWant, self.cuiMode, self.block
    self.cuiWant, self.cuiMode, self.cuiTarget = nil, nil, nil
    onQuestClick(want, self.questID, blk, self, mode or false)
end

local hoverOn, hoverOff   -- definis plus bas (survol)

local function ensureClick()
    if click then return click end
    if InCombatLockdown() or not microButton() then return nil end
    pick = CreateFrame("Button", PICK_NAME, UIParent, "SecureActionButtonTemplate")
    pick:SetAttribute("type", "click")
    -- agit au relachement, comme le /click de la macro (sans parametre)
    pick:SetAttribute("useOnKeyDown", false)
    pick:RegisterForClicks("AnyUp")
    pick:Hide()
    click = CreateFrame("Button", "CorpUIQuestsClick", UIParent, "SecureActionButtonTemplate")
    -- appui ET relachement (comme les zones d Infos) ; jamais ancre a une
    -- ligne ni a un texte : place en coordonnees absolues, hors combat
    click:RegisterForClicks("AnyUp", "AnyDown")
    click:Hide()
    click:SetScript("PreClick", preClick)
    click:SetScript("PostClick", postClick)
    -- (reste visible en combat si le verrou a devance PLAYER_REGEN_DISABLED)
    click:SetScript("OnEnter", function(self)
        local blk = self.questID and blocks[self.questID]
        if blk then hoverOn(blk) end
    end)
    click:SetScript("OnLeave", function() hoverOff() end)
    return click
end

-- pose le bouton securise sur le bloc de la quete (hors combat)
local function placeClick(blk)
    if combat() or ns.moversShown then return end
    local c = ensureClick()
    if not c then return end
    local top, left, right = body:GetTop(), body:GetLeft(), body:GetRight()
    if not (top and left and right) then c:Hide() return end
    -- meme echelle que la liste : ses coordonnees valent pour le bouton
    c:SetScale(body:GetEffectiveScale() / UIParent:GetEffectiveScale())
    c:SetFrameStrata(frame:GetFrameStrata())
    c:SetFrameLevel(frame:GetFrameLevel() + 20)
    c:ClearAllPoints()
    c:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, top - blk.y2 + 1)
    c:SetSize(math.max(8, right - left), math.max(8, blk.y2 - blk.y1))
    c.questID, c.block, c.y1, c.y2 = blk.id, blk, blk.y1, blk.y2
    c:Show()
end

---------------------------------------------------------------------------
-- Survol : surbrillance du bloc, infobulle, bouton securise
---------------------------------------------------------------------------

-- couleur d une ligne de donnees d infobulle (ColorMixin ou { r, g, b })
local function lineRGB(c)
    if type(c) ~= "table" then return 1, 1, 1 end
    if c.GetRGB then
        local ok, r, g, b = pcall(c.GetRGB, c)
        if ok and type(r) == "number" then return r, g, b end
    end
    if type(c.r) == "number" then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function plainText(v)
    return not issecret(v) and type(v) == "string" and v ~= ""
end

-- membres du groupe sur la quete et ou ils en sont, comme l infobulle du
-- suivi de Blizzard : on lit ses donnees (C_TooltipInfo) et on les ajoute a
-- la notre (SetQuestPartyProgress effacerait l infobulle)
local function addPartyProgress(t, questID)
    if not IsInGroup() or not C_TooltipInfo or not C_TooltipInfo.GetQuestPartyProgress then return false end
    local on = false
    local okN, count = pcall(GetNumSubgroupMembers)
    for i = 1, (okN and not issecret(count) and count or 0) do
        local ok, v = pcall(C_QuestLog.IsUnitOnQuest, "party" .. i, questID)
        if ok and not issecret(v) and v then on = true break end
    end
    if not on then return false end
    local ok, data = pcall(C_TooltipInfo.GetQuestPartyProgress, questID, true, true)
    if not ok or issecret(data) or type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    t:AddLine(" ")
    t:AddLine(gstr("PARTY_QUEST_STATUS_ON", L.QUESTS_PARTY), 1, 1, 1)
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if plainText(text) then
            local r, g, b = lineRGB(line.leftColor)
            if plainText(line.rightText) then
                local rr, rg, rb = lineRGB(line.rightColor)
                pcall(t.AddDoubleLine, t, text, line.rightText, r, g, b, rr, rg, rb)
            else
                pcall(t.AddLine, t, text, r, g, b, true)
            end
        end
    end
    return true
end

local function showTip(blk)
    local C = ns.COLORS
    -- infobulle du cote ou il y a de la place
    local x = frame:GetCenter()
    local right = x and (x * frame:GetEffectiveScale() > UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2)
    local t = ns.Tooltip(blk.first, right and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
    t:AddLine(blk.title, C.gold[1], C.gold[2], C.gold[3])
    -- groupe : un blanc entre sa progression et les aides
    if addPartyProgress(t, blk.id) then t:AddLine(" ") end
    tipCombat = combat() and true or false
    if tipCombat then
        t:AddLine(L.QUESTS_TIP_COMBAT, 1, 0.45, 0.45)
    else
        t:AddLine(L.QUESTS_TIP_CLICK, 0.5, 0.8, 1)
    end
    t:AddLine(L.QUESTS_TIP_RIGHT, 0.5, 0.8, 1)
    t:AddLine(L.QUESTS_TIP_SHIFT, 0.5, 0.8, 1)
    t:Show()
end

-- refresh : mise a jour de la liste pendant le survol (pas de nouvelle infobulle)
hoverOn = function(blk, refresh)
    hoverID = blk.id
    hover:ClearAllPoints()
    hover:SetPoint("TOPLEFT", body, "TOPLEFT", 1, -(blk.y1 - 1))
    hover:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT", -1, -(blk.y2 - 1))
    hover:Show()
    if not refresh or tipCombat ~= (combat() and true or false) then showTip(blk) end
    placeClick(blk)
end

hoverOff = function()
    local was = hoverID
    hoverID = nil
    -- (cacher le bouton sous la souris relance OnLeave : hoverID deja nil)
    if click and click:IsShown() and not InCombatLockdown() then click:Hide() end
    if not was then return end
    if hover then hover:Hide() end
    ns.HideTooltip()
end

---------------------------------------------------------------------------
-- Affichage
---------------------------------------------------------------------------

local function line(i)
    local fs = lines[i]
    if not fs then
        fs = CreateFrame("Button", nil, body)
        fs.text = fs:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs.text:SetPoint("TOPLEFT")
        fs.text:SetPoint("TOPRIGHT")
        fs.text:SetJustifyH("LEFT")
        fs.text:SetWordWrap(true)
        -- texte de droite (niveau de la quete, style Moderne)
        fs.right = fs:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs.right:SetPoint("TOPRIGHT", 0, -1)
        fs.right:SetJustifyH("RIGHT")
        fs.right:Hide()
        -- sans le bouton securise (combat) : clic droit, Maj + clic
        fs:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        fs:SetScript("OnClick", function(self, button)
            onQuestClick(wants(button), self.questID, self.block, self)
        end)
        fs:SetScript("OnEnter", function(self)
            if self.block then hoverOn(self.block) end
        end)
        fs:SetScript("OnLeave", function()
            -- le bouton securise vient de se poser dessus : meme quete
            if click and click:IsShown() and click:IsMouseOver() then return end
            hoverOff()
        end)
        lines[i] = fs
    end
    return fs
end

-- right, rr, rg, rb : texte court a droite de la ligne (niveau), facultatif
local function setLine(i, y, text, font, r, g, b, indent, questID, right, rr, rg, rb)
    local l = line(i)
    l.text:SetFontObject(font)
    l.text:SetText(text)
    l.text:SetTextColor(r, g, b)
    l.text:ClearAllPoints()
    l.text:SetPoint("TOPLEFT")
    if right then
        l.right:SetText(right)
        l.right:SetTextColor(rr or 1, rg or 1, rb or 1)
        l.right:Show()
        l.text:SetPoint("TOPRIGHT", -22, 0)
    else
        l.right:Hide()
        l.text:SetPoint("TOPRIGHT")
    end
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", body, "TOPLEFT", indent, -y)
    l:SetWidth(WIDTH - 12 - indent)
    local h = math.max(10, l.text:GetStringHeight() or 0)
    l:SetHeight(h)
    l.questID = questID
    l:EnableMouse(questID ~= nil)
    l:Show()
    return y + h + 2
end

local function update()
    if not frame then return end
    if not db.enabled then hoverOff() frame:Hide() return end
    local quests = watchedQuests()
    -- aucune quete suivie : le suivi disparait (sauf pendant le placement
    -- des cadres, pour pouvoir encore le deplacer)
    if #quests == 0 and not ns.moversShown then
        hoverOff()
        syncMenu()
        frame:Hide()
        return
    end
    frame:Show()
    if #quests == 0 then
        header.count:SetText("")
    else
        header.count:SetText(tostring(#quests))
    end
    header.toggle.label:SetText(db.collapsed and "+" or "−")
    for _, l in ipairs(lines) do l:Hide() l.block = nil end
    for k in pairs(blocks) do blocks[k] = nil end
    if db.collapsed or #quests == 0 then
        hoverOff()
        syncMenu()
        body:SetHeight(1)
        ns.NoSnap(body)
        body:SetShown(false)
        frame:SetHeight(24)
        if #quests == 0 and not db.collapsed then
            body:SetShown(true)
            local y = setLine(1, 4, L.QUESTS_NONE, "GameFontDisableSmall", 0.6, 0.6, 0.6, 4)
            body:SetHeight(y + 4)
            frame:SetHeight(24 + y + 6)
        end
        return
    end
    body:Show()
    local y, n = 4, 0
    for qi, id in ipairs(quests) do
        if qi > MAX_QUESTS then break end
        local q = questData(id)
        if q then
            local r, g, b = levelColor(q.level)
            -- bloc de la quete : titre + objectifs, tous cliquables
            local blk = { id = id, title = q.title, y1 = y }
            n = n + 1
            local first = n
            -- titre et niveau a droite dans la couleur de difficulte
            y = setLine(n, y, q.title, "GameFontNormal", r, g, b, 4, id, tostring(q.level), r, g, b)
            if q.complete then
                n = n + 1
                y = setLine(n, y, L.QUESTS_READY, "GameFontHighlightSmall", 0.3, 0.9, 0.3, 14, id)
            else
                for _, o in ipairs(q.objectives) do
                    local text = o.text or ""
                    if text ~= "" then
                        n = n + 1
                        local done = o.finished
                        y = setLine(n, y, (done and "- " or "- ") .. text, "GameFontHighlightSmall",
                            done and 0.35 or 0.85, done and 0.85 or 0.85, done and 0.35 or 0.85, 14, id)
                    end
                end
            end
            blk.first, blk.y2 = lines[first], y
            for k = first, n do lines[k].block = blk end
            blocks[id] = blk
            y = y + 4
        end
    end
    body:SetHeight(y)
    frame:SetHeight(24 + y + 4)
    -- survol en cours : suivre la quete a sa nouvelle place
    if hoverID then
        local blk = blocks[hoverID]
        if blk then hoverOn(blk, true) else hoverOff() end
    end
    syncMenu()
    -- bouton securise reste en place pendant le combat (on ne peut plus le
    -- deplacer) : si sa quete a bouge, il ne doit plus agir sur elle
    if click and click:IsShown() and click.questID then
        local blk = blocks[click.questID]
        if not blk or blk.y1 ~= click.y1 or blk.y2 ~= click.y2 then click.questID = nil end
    end
    -- quete abandonnee / rendue : la confirmation n a plus lieu d etre
    if confirm and confirm:IsShown() then
        local idx = safe(C_QuestLog.GetLogIndexForQuestID, confirm.questID)
        if not issecret(idx) and not idx then confirm:Hide() end
    end
end

local function schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        update()
    end)
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function build()
    db.pos = db.pos or { point = "TOPRIGHT", x = -90, y = -230 }
    local C = ns.COLORS
    frame = CreateFrame("Frame", "CorpUIQuests", UIParent)
    frame:SetSize(WIDTH, 24)
    frame:SetFrameStrata("LOW")
    ns.ApplyPos(frame, db.pos)

    -- en-tete : titre, nombre, bouton replier
    header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(22)
    -- pas de bandeau : un filet fin sous le titre
    local rule = header:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT", 0, 1)
    rule:SetPoint("BOTTOMRIGHT", 0, 1)
    rule:SetHeight(1)
    ns.NoSnap(rule)
    rule:SetColorTexture(1, 1, 1, 0.22)
    header.title = header:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(header.title, 12)
    header.title:SetPoint("LEFT", 2, 0)
    header.title:SetTextColor(0.93, 0.93, 0.93)
    header.title:SetText(L.QUESTS_TITLE)
    header.count = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header.count:SetPoint("LEFT", header.title, "RIGHT", 6, 0)
    header.toggle = CreateFrame("Button", nil, header)
    header.toggle:SetSize(18, 18)
    header.toggle:SetPoint("RIGHT", -3, 0)
    header.toggle.label = header.toggle:CreateFontString(nil, "OVERLAY")
    ns.UI.HeadFont(header.toggle.label, 14)
    header.toggle.label:SetPoint("CENTER", 0, 1)
    header.toggle:SetScript("OnClick", function()
        db.collapsed = not db.collapsed
        update()
    end)

    -- corps : fond leger sous la liste
    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
    body:SetHeight(1)
    ns.NoSnap(body)
    -- pas de fond : la liste est posee sur le jeu
    -- surbrillance de la quete survolee (tout son bloc)
    hover = body:CreateTexture(nil, "BORDER")
    ns.UI.Gradient(hover, "HORIZONTAL", C.violet[1], C.violet[2], C.violet[3], 0.32, C.violet[1], C.violet[2], C.violet[3], 0.04)
    hover:Hide()

    ns.UI.Mover(frame, db.pos, L.QUESTS_TITLE)
end

local function applyBlizzard()
    if InCombatLockdown() then return end
    ns.HideBlizzard(BLIZZ, db.enabled and db.hideBlizzard)
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local win

local function buildWindow()
    win = ns.UI.Window("CorpUIQuestsOptions", ns.TITLE .. " - " .. L.MOD_QUESTS, nil, 440, 236)
    -- chaque case applique elle-meme son effet (pas de onChange commun)
    local form = ns.UI.Form(win, -34)
    form:Check(L.QUESTS_OPT_ENABLE, function() return db.enabled end,
        function(v) db.enabled = v update() applyBlizzard() end)
    form:Check(L.QUESTS_OPT_BLIZZ, function() return db.hideBlizzard end,
        function(v) db.hideBlizzard = v applyBlizzard() end)
    -- quetes acceptees / rendues seules : reglage du module Experience
    -- (CorpUIDB.xp.autoQuest, cree a sa connexion), lu par lui a chaque
    -- dialogue de PNJ : l ecrire suffit
    form:Check(L.XP_OPT_AUTOQUEST, function()
        local xp = ns.InitRoot().xp
        return xp and xp.autoQuest
    end, function(v)
        local xp = ns.InitRoot().xp
        if xp then xp.autoQuest = v end
    end)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 8, form.y - 6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.QUESTS_HINT)
    win:HookScript("OnShow", function() form:Refresh() end)
end

local function toggle()
    if not win then buildWindow() end
    ns.ShowPanel(win)
end

---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if ns.ModuleOff("quetes", ev) then return end
    if event == "PLAYER_LOGIN" then
        local root = ns.InitRoot()
        root.quests = root.quests or {}
        db = root.quests
        if db.enabled == nil then db.enabled = true end
        if db.hideBlizzard == nil then db.hideBlizzard = true end
        build()
        applyBlizzard()
        update()
        -- placement des cadres ouvert / ferme : le suivi vide se montre / se cache
        ns.Listen(function() if db then schedule() end end)
    elseif db then
        if event == "PLAYER_REGEN_DISABLED" then
            -- juste avant le verrouillage : on range le bouton securise
            -- (la ligne sous la souris reprend la main : clic droit, Maj)
            fighting = true
            if click and not InCombatLockdown() then
                arm(nil)
                click:Hide()
            end
            if hoverID and blocks[hoverID] then hoverOn(blocks[hoverID], true) end
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            fighting = false
            applyBlizzard()
        end
        schedule()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE",
                     "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
                     "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
-- journal des membres du groupe : pas le notre
if not pcall(ev.RegisterUnitEvent, ev, "UNIT_QUEST_LOG_CHANGED", "player") then
    pcall(ev.RegisterEvent, ev, "UNIT_QUEST_LOG_CHANGED")
end

ns.RegisterModule({
    command = "quetes",
    alias = "quests",
    panelName = "CorpUIQuestsOptions",
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    title = function() return L.MOD_QUESTS end,
    desc = function() return L.QUESTS_DESC end,
    Slash = function() toggle() end,
    Open = toggle,
})
