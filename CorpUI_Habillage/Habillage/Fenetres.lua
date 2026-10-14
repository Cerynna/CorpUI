--[[--------------------------------------------------------------------------
    CorpUI - module Habillage : liste des fenetres de Blizzard habillees

    Rangees par groupe : une case par groupe dans le panneau du module.
    Noms et morceaux releves dans le code de ce client (depot
    Gethe/wow-ui-source, branche forever : variantes Camelot quand le .toc
    les charge, sinon Mainline). Une fenetre absente est simplement ignoree.

    Champs d une fenetre :
      [1]       nom global du cadre
      fade      morceaux decoratifs en plus a effacer : chemin depuis la
                fenetre ("RightPaneHost", "BorderFrame.NineSlice") ou depuis
                une globale ("G:CharacterModelScene.BackgroundOverlay").
                Une texture passe a alpha 0 ; un cadre perd ses textures a
                lui (pas celles de ses enfants).
      keep      true : garder les textures posees sur la fenetre elle-meme
                (parchemins au texte sombre, icones des popups...)
      keepDecor morceaux standard a ne pas effacer (ex. "Background")
      walk      sous-cadres ou chercher boutons et onglets (defaut : fenetre)
      depth     profondeur de cette recherche (defaut 6, 0 = aucune)
      inset     { gauche, haut, droite, bas } : retrait de notre fond
      edge      cadre d une strate superieure qui recoit le liseré et le
                bandeau, le fond restant sur la fenetre (carte du monde)
      buttons   boutons a textures simples a aplatir (popups)
      noHead    pas de bandeau d accent en haut (titre hors du cadre)
      close     chemin de la croix si elle n est pas a l endroit habituel
      title     chemin du titre a passer en or (sinon cherche tout seul)
----------------------------------------------------------------------------]]

local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)

local CALENDAR_BORDER = {}
for _, side in ipairs({ "Top", "Bottom" }) do
    for _, pos in ipairs({ "Left", "Middle", "Right" }) do
        table.insert(CALENDAR_BORDER, "G:CalendarFrame" .. side .. pos .. "Texture")
    end
end
for _, side in ipairs({ "Left", "Right" }) do
    for _, pos in ipairs({ "Top", "Middle", "Bottom" }) do
        table.insert(CALENDAR_BORDER, "G:CalendarFrame" .. side .. pos .. "Texture")
    end
end

local POPUP = {
    keep = true, noHead = true, depth = 0,
    buttons = { "ButtonContainer.Button1", "ButtonContainer.Button2", "ButtonContainer.Button3",
                "ButtonContainer.Button4", "ExtraButton" },
}
local function popup(name)
    local t = { name }
    for k, v in pairs(POPUP) do t[k] = v end
    return t
end

ns.SKIN_GROUPS = {
    -- fiche personnage : reputation, competences et monnaies sont des
    -- volets de CharacterFrame (variante Camelot)
    { key = "character", label = "SKINS_G_CHARACTER", windows = {
        { "CharacterFrame", fade = {
            "LeftPaneHost", "RightPaneHost",
            "G:CharacterStatsPaneScrollBox.Border", "G:CharacterStatsPaneScrollBox.ClassBackground",
            "G:CharacterStatsPanePetScrollBox.Border",
            "G:CharacterModelScene.BackgroundTopLeft", "G:CharacterModelScene.BackgroundTopRight",
            "G:CharacterModelScene.BackgroundBotLeft", "G:CharacterModelScene.BackgroundBotRight",
            "G:CharacterModelScene.BackgroundOverlay",
            "G:PaperDollFrame.TitleManagerPane.Border", "G:PaperDollFrame.EquipmentManagerPane.Border",
        } },
        { "InspectFrame" },
        { "DressUpFrame" },
    } },

    -- grimoire et talents (Blizzard_PlayerSpells, charge a la demande)
    -- le detail du grimoire est repris par Grimoire.lua (Skins ne descend
    -- pas dans SpellBookFrame : parchemin eteint, panneaux a nous)
    { key = "spells", label = "SKINS_G_SPELLS", windows = {
        { "PlayerSpellsFrame", depth = 3 },
        { "SpellBookFrame" },
        { "TalentFrame" },
        { "PlayerTalentFrame" },
    } },

    -- carte du monde et journal de quetes : cadre exterieur seulement,
    -- la carte et le contenu du journal ne bougent pas
    { key = "map", label = "SKINS_G_MAP", windows = {
        { "WorldMapFrame", edge = "BorderFrame", walk = { "BorderFrame" }, depth = 1,
          close = "BorderFrame.CloseButton", title = "BorderFrame.TitleContainer.TitleText",
          fade = {
            "BorderFrame.NineSlice", "BorderFrame.PortraitContainer", "BorderFrame.TitleContainer",
            "BorderFrame.Bg", "BorderFrame.TopTileStreaks", "BorderFrame.InsetBorderTop",
            "G:QuestScrollFrame.BorderFrame", "G:QuestMapFrame.QuestsFrame.DetailsFrame.BorderFrame",
        } },
    } },

    -- dialogues des PNJ : l interieur de GossipFrame et de QuestFrame est
    -- repris par PNJ.lua (parchemin eteint, textes clairs) ; ailleurs le
    -- parchemin reste (texte sombre dessus)
    { key = "npc", label = "SKINS_G_NPC", windows = {
        { "GossipFrame", keepDecor = { "Background" }, keep = true },
        { "QuestFrame" },
        { "ItemTextFrame", keep = true },
        -- la carte des trajets est dessinee par Blizzard dans InsetBg
        -- (SetTaxiMap(self.InsetBg)) : a garder
        { "TaxiFrame", spare = { "InsetBg" } },
        { "FlightMapFrame" },
        { "TabardFrame" },
        { "PetitionFrame", keep = true },
        { "GuildRegistrarFrame", keep = true },
        { "PetStableFrame" },
        { "StableFrame" },
    } },

    -- social : amis, guilde / communautes, recherche de groupe, calendrier
    { key = "social", label = "SKINS_G_SOCIAL", windows = {
        { "FriendsFrame" },
        -- contacts (Blizzard_SocialUI, celle affichee sur ce client) :
        -- l interieur est repris par Social.lua
        { "SocialUIFrame", depth = 3 },
        -- canaux de discussion (Blizzard_Channels) : tout l interieur est
        -- repris par Canaux.lua, Skins.lua ne fait que le cadre
        { "ChannelFrame", depth = 0 },
        { "CommunitiesFrame", depth = 3 },
        { "GuildFrame" },
        -- recherche de groupe facon Vanilla (Blizzard_GroupFinder_VanillaStyle) :
        -- la zone cliquable s arrete 30 px avant la droite, 74 px avant le bas
        { "LFGParentFrame", inset = { 0, 0, 30, 74 } },
        { "PVEFrame" },
        { "CalendarFrame", keep = true, fade = CALENDAR_BORDER, noHead = true, depth = 1,
          close = "G:CalendarCloseButton" },
    } },

    -- commerce : marchand, banque, courrier, hotel des ventes, echange
    { key = "trade", label = "SKINS_G_TRADE", windows = {
        { "MerchantFrame" },
        { "BankFrame" },
        { "MailFrame" },
        { "OpenMailFrame", keep = true },
        { "AuctionHouseFrame", depth = 4 },
        { "AuctionFrame" },
        { "TradeFrame" },
        { "GuildBankFrame" },
        { "LootFrame" },
    } },

    -- metiers et maitres
    { key = "prof", label = "SKINS_G_PROF", windows = {
        { "ProfessionsFrame", depth = 3 },
        { "ProfessionsBookFrame" },
        { "TradeSkillFrame" },
        { "CraftFrame" },
        { "ClassTrainerFrame" },
    } },

    -- menu du jeu, options, fenetres systeme
    { key = "system", label = "SKINS_G_SYSTEM", windows = {
        { "GameMenuFrame", fade = { "Header" }, title = "Header.Text", noHead = true },
        { "SettingsPanel", depth = 2 },
        { "AddonList" },
        { "MacroFrame" },
        { "ChatConfigFrame" },
        { "HelpFrame" },
        { "KeyBindingFrame" },
        { "CollectionsJournal" },
        { "EncounterJournal" },
        { "WardrobeFrame" },
        { "TimeManagerFrame" },
    } },

    -- Heritage (Blizzard_LegacySystem, propre a Camelot, charge a la
    -- demande) : l interieur est repris par Heritage.lua
    { key = "legacy", label = "SKINS_G_LEGACY", windows = {
        { "LegacySystemFrame" },
    } },

    -- fenetres de confirmation (StaticPopup1 a 4)
    { key = "popups", label = "SKINS_G_POPUPS", windows = {
        popup("StaticPopup1"), popup("StaticPopup2"), popup("StaticPopup3"), popup("StaticPopup4"),
    } },
}
