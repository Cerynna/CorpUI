--[[--------------------------------------------------------------------------
    CorpUI - sons proposes dans les reglages (noyau)
    Liste (sons du jeu, fichiers de CorpUI, sons rigolos), lecture par cle
    (ns.PlaySoundKey) et choix pour ns.UI.Select (ns.SoundChoices). Venue
    de Dissipation : Chasseur, Podometre... s en servent aussi.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

-- sons proposes : numero du jeu (SOUNDKIT si le client le connait)
-- sons du jeu (SoundKitConstants, branche forever) : nom de la constante,
-- numero de repli ; libelle DSP_SOUND_<CLE>. Le choix dans la liste joue le son.
local SOUND_LIST = {
    { "none" },
    { title = "DSP_GROUP_GAME" },
    { "soft", "TELL_MESSAGE", 3081 },
    { "ping", "MAP_PING", 3175 },
    { "invite", "IG_PLAYER_INVITE", 880 },
    { "toast", "UI_BNET_TOAST", 18019 },
    { "tuto", "TUTORIAL_POPUP", 7355 },
    { "coin", "LOOT_WINDOW_COIN_SOUND", 120 },
    { "quest", "IG_QUEST_LIST_COMPLETE", 878 },
    { "bell", "ALARM_CLOCK_WARNING_3", 12889 },
    { "alarm1", "ALARM_CLOCK_WARNING_1", 18871 },
    { "alarm2", "ALARM_CLOCK_WARNING_2", 12867 },
    { "ready", "READY_CHECK", 8960 },
    { "role", "LFG_ROLE_CHECK", 17317 },
    { "pvp", "PVP_THROUGH_QUEUE", 8459 },
    { "gm", "GM_CHAT_WARNING", 15273 },
    { "raid", "RAID_WARNING", 8959 },
    { "boss", "RAID_BOSS_EMOTE_WARNING", 12197 },
    -- fichiers de CorpUI (Media\Sons, licences libres, voir CREDITS.txt) ;
    -- un fichier ajoute n est vu par le jeu qu apres son redemarrage
    { title = "DSP_GROUP_CORPUI" },
    { "f_ding", file = "ding" },
    { "f_dinggrave", file = "ding_grave" },
    { "f_carillon", file = "carillon" },
    { "f_bong", file = "bong" },
    { "f_verre", file = "verre" },
    { "f_question", file = "question" },
    { "f_confirm1", file = "confirmation1" },
    { "f_confirm2", file = "confirmation2" },
    { "f_montee", file = "montee" },
    { "f_tambour", file = "tambour" },
    { "f_alarme", file = "alarme" },
    { "f_alarmelongue", file = "alarme_longue" },
    { "f_erreur1", file = "erreur1" },
    { "f_erreur2", file = "erreur2" },
    { "f_refus", file = "refus" },
    { title = "DSP_GROUP_FUN" },
    { "f_trombone", file = "trombone" },
    { "f_klaxon", file = "klaxon" },
    { "f_sonnette", file = "sonnette" },
    { "f_sorciere", file = "sorciere" },
    { "f_paon", file = "paon" },
    { "f_bizarre1", file = "bizarre1", weird = 1 },
    { "f_bizarre2", file = "bizarre2", weird = 2 },
    { "f_bizarre3", file = "bizarre3", weird = 3 },
    { "f_bizarre4", file = "bizarre4", weird = 4 },
    { "f_bizarre5", file = "bizarre5", weird = 5 },
    { "f_bizarre6", file = "bizarre6", weird = 6 },
    { "f_bizarre7", file = "bizarre7", weird = 7 },
    { "f_bizarre8", file = "bizarre8", weird = 8 },
}
local SOUNDS, SOUND_KIT, SOUND_FILE = {}, {}, {}
for _, s in ipairs(SOUND_LIST) do
    if s[1] then SOUNDS[#SOUNDS + 1] = s[1] end
    if s[2] then SOUND_KIT[s[1]] = { s[2], s[3] } end
    if s.file then SOUND_FILE[s[1]] = (ns.MEDIA or "Interface\\AddOns\\CorpUI\\Media\\") .. "Sons\\" .. s.file .. ".ogg" end
end

local function soundId(key)
    local k = SOUND_KIT[key]
    if not k then return nil end
    local v = SOUNDKIT and SOUNDKIT[k[1]]
    if type(v) == "number" then return v end
    return k[2]
end

local function playSound(key)
    local file = SOUND_FILE[key]
    if file then
        if PlaySoundFile then pcall(PlaySoundFile, file, "Master") end
        return
    end
    local id = soundId(key)
    if id and PlaySound then pcall(PlaySound, id, "Master") end
end

-- lecture et choix, partages par les modules
ns.PlaySoundKey = playSound
function ns.SoundChoices()
    local list = {}
    for _, s in ipairs(SOUND_LIST) do
        if s.title then
            list[#list + 1] = { title = true, value = "#" .. s.title, text = L[s.title] }
        else
            local text = L["DSP_SOUND_" .. s[1]:upper()]
            if s.weird then text = string.format(L.DSP_SOUND_WEIRD, s.weird) end
            list[#list + 1] = { value = s[1], text = text or s[1] }
        end
    end
    return list
end

