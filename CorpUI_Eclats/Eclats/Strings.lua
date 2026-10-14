local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)

-- Textes du module Eclats (Eclats\Eclats.lua)
ns.AddStrings({
    enUS = {
        MOD_SPARKLES = "Loot sparkles", SPARK_DESC = "quest items always sparkle; herbs and ore veins sparkle as you approach them",
        SPARK_OPT_LOOT = "Quest items sparkle (the game's loot effect)",
        SPARK_LOOT_NOTE = "Graphics presets turn it off: it is put back. Unticking it only removes the sparkle after restarting the game.",
        SPARK_H_NODES = "Sparkles while approaching", SPARK_OPT_ORE = "Ore veins", SPARK_OPT_HERB = "Herbs", SPARK_OPT_QUEST = "Quest objects",
        SPARK_HINT = "Uses the game's soft targeting: the nearest object within about 15 yards sparkles (dim out of reach, bright once you can gather it, grey if you can't) and shows the gathering icon. Not in combat. Your soft targeting settings are restored when nothing is ticked.",
    },
    frFR = {
        MOD_SPARKLES = "Éclats du butin", SPARK_DESC = "les objets de quête scintillent toujours ; herbes et filons scintillent à l'approche",
        SPARK_OPT_LOOT = "Objets de quête scintillants (effet de butin du jeu)",
        SPARK_LOOT_NOTE = "Les réglages graphiques le coupent : il est remis. Décocher n'enlève l'étincelle qu'au redémarrage du jeu.",
        SPARK_H_NODES = "Éclats à l'approche", SPARK_OPT_ORE = "Filons", SPARK_OPT_HERB = "Herbes", SPARK_OPT_QUEST = "Objets de quête",
        SPARK_HINT = "Utilise le ciblage doux du jeu : l'objet le plus proche, à 15 m environ, scintille (terne hors de portée, vif quand tu peux le ramasser, gris si tu ne peux pas) et montre l'icône de récolte. Pas en combat. Tes réglages de ciblage doux reviennent quand rien n'est coché.",
    },
    deDE = {
        MOD_SPARKLES = "Beutefunkeln", SPARK_DESC = "Questgegenstände funkeln immer; Kräuter und Erzadern funkeln beim Näherkommen",
        SPARK_OPT_LOOT = "Questgegenstände funkeln (Beuteeffekt des Spiels)",
        SPARK_LOOT_NOTE = "Grafikvoreinstellungen schalten ihn ab: er wird wieder gesetzt. Abwählen entfernt das Funkeln erst nach einem Neustart des Spiels.",
        SPARK_H_NODES = "Funkeln beim Näherkommen", SPARK_OPT_ORE = "Erzadern", SPARK_OPT_HERB = "Kräuter", SPARK_OPT_QUEST = "Questobjekte",
        SPARK_HINT = "Nutzt die weiche Zielerfassung des Spiels: das nächste Objekt im Umkreis von etwa 15 m funkelt (blass außer Reichweite, hell in Reichweite, grau wenn nicht sammelbar) und zeigt das Sammelsymbol. Nicht im Kampf. Deine Einstellungen kommen zurück, wenn nichts angehakt ist.",
    },
    esES = {
        MOD_SPARKLES = "Destellos del botín", SPARK_DESC = "los objetos de misión siempre brillan; hierbas y filones brillan al acercarte",
        SPARK_OPT_LOOT = "Los objetos de misión brillan (efecto de botín del juego)",
        SPARK_LOOT_NOTE = "Los ajustes gráficos lo desactivan: se vuelve a poner. Desmarcarlo solo quita el brillo tras reiniciar el juego.",
        SPARK_H_NODES = "Destellos al acercarte", SPARK_OPT_ORE = "Filones", SPARK_OPT_HERB = "Hierbas", SPARK_OPT_QUEST = "Objetos de misión",
        SPARK_HINT = "Usa el objetivo suave del juego: el objeto más cercano, a unos 15 m, brilla (tenue fuera de alcance, intenso cuando puedes recogerlo, gris si no puedes) y muestra el icono de recolección. No en combate. Tus ajustes vuelven cuando no hay nada marcado.",
    },
    ptBR = {
        MOD_SPARKLES = "Brilho do saque", SPARK_DESC = "itens de missão sempre brilham; ervas e veios brilham ao se aproximar",
        SPARK_OPT_LOOT = "Itens de missão brilham (efeito de saque do jogo)",
        SPARK_LOOT_NOTE = "As predefinições gráficas o desligam: ele é recolocado. Desmarcar só tira o brilho depois de reiniciar o jogo.",
        SPARK_H_NODES = "Brilho ao se aproximar", SPARK_OPT_ORE = "Veios de minério", SPARK_OPT_HERB = "Ervas", SPARK_OPT_QUEST = "Objetos de missão",
        SPARK_HINT = "Usa o alvo suave do jogo: o objeto mais próximo, a uns 15 m, brilha (fraco fora de alcance, forte quando dá para coletar, cinza se não der) e mostra o ícone de coleta. Não em combate. Suas configurações voltam quando nada está marcado.",
    },
    itIT = {
        MOD_SPARKLES = "Scintille del bottino", SPARK_DESC = "gli oggetti delle missioni brillano sempre; erbe e vene scintillano avvicinandosi",
        SPARK_OPT_LOOT = "Gli oggetti delle missioni brillano (effetto bottino del gioco)",
        SPARK_LOOT_NOTE = "Le preimpostazioni grafiche lo spengono: viene rimesso. Togliere la spunta rimuove la scintilla solo dopo il riavvio del gioco.",
        SPARK_H_NODES = "Scintille avvicinandosi", SPARK_OPT_ORE = "Vene di minerale", SPARK_OPT_HERB = "Erbe", SPARK_OPT_QUEST = "Oggetti delle missioni",
        SPARK_HINT = "Usa il bersaglio morbido del gioco: l'oggetto più vicino, entro circa 15 m, scintilla (tenue fuori portata, vivo quando puoi raccoglierlo, grigio se non puoi) e mostra l'icona di raccolta. Non in combattimento. Le tue impostazioni tornano quando nulla è spuntato.",
    },
    ruRU = {
        MOD_SPARKLES = "Блеск добычи", SPARK_DESC = "предметы заданий всегда сверкают; травы и рудные жилы сверкают при приближении",
        SPARK_OPT_LOOT = "Предметы заданий сверкают (эффект добычи игры)",
        SPARK_LOOT_NOTE = "Графические пресеты отключают его: он возвращается. Снятие флажка убирает блеск только после перезапуска игры.",
        SPARK_H_NODES = "Блеск при приближении", SPARK_OPT_ORE = "Рудные жилы", SPARK_OPT_HERB = "Травы", SPARK_OPT_QUEST = "Объекты заданий",
        SPARK_HINT = "Использует мягкое наведение игры: ближайший объект в пределах ~15 м сверкает (тускло вне досягаемости, ярко, когда можно собрать, серым, если нельзя) и показывает значок сбора. Не в бою. Ваши настройки возвращаются, когда ничего не отмечено.",
    },
    zhCN = {
        MOD_SPARKLES = "拾取闪光", SPARK_DESC = "任务物品始终闪光；靠近时草药和矿脉也会闪光",
        SPARK_OPT_LOOT = "任务物品闪光（游戏的拾取效果）",
        SPARK_LOOT_NOTE = "图形预设会关闭它：会被重新开启。取消勾选要在重启游戏后才会去掉闪光。",
        SPARK_H_NODES = "靠近时闪光", SPARK_OPT_ORE = "矿脉", SPARK_OPT_HERB = "草药", SPARK_OPT_QUEST = "任务物体",
        SPARK_HINT = "使用游戏的软目标：约 15 码内最近的物体会闪光（超出范围时暗淡，可采集时明亮，无法采集时灰色）并显示采集图标。战斗中不显示。全部取消勾选时恢复你原来的设置。",
    },
    zhTW = {
        MOD_SPARKLES = "拾取閃光", SPARK_DESC = "任務物品始終閃光；靠近時草藥和礦脈也會閃光",
        SPARK_OPT_LOOT = "任務物品閃光（遊戲的拾取效果）",
        SPARK_LOOT_NOTE = "圖形預設會關閉它：會被重新開啟。取消勾選要在重啟遊戲後才會去掉閃光。",
        SPARK_H_NODES = "靠近時閃光", SPARK_OPT_ORE = "礦脈", SPARK_OPT_HERB = "草藥", SPARK_OPT_QUEST = "任務物件",
        SPARK_HINT = "使用遊戲的軟目標：約 15 碼內最近的物件會閃光（超出範圍時暗淡，可採集時明亮，無法採集時灰色）並顯示採集圖示。戰鬥中不顯示。全部取消勾選時恢復你原來的設定。",
    },
    koKR = {
        MOD_SPARKLES = "전리품 반짝임", SPARK_DESC = "퀘스트 아이템이 항상 반짝이고, 가까이 가면 약초와 광맥도 반짝입니다",
        SPARK_OPT_LOOT = "퀘스트 아이템 반짝임 (게임의 전리품 효과)",
        SPARK_LOOT_NOTE = "그래픽 프리셋이 이를 끄면 다시 켭니다. 체크를 해제하면 게임을 다시 시작한 뒤에야 반짝임이 사라집니다.",
        SPARK_H_NODES = "가까이 갈 때 반짝임", SPARK_OPT_ORE = "광맥", SPARK_OPT_HERB = "약초", SPARK_OPT_QUEST = "퀘스트 물체",
        SPARK_HINT = "게임의 소프트 대상 지정을 사용합니다: 약 15미터 안의 가장 가까운 물체가 반짝이며 (사거리 밖에서는 흐리게, 채집 가능하면 밝게, 불가능하면 회색) 채집 아이콘을 보여 줍니다. 전투 중에는 표시되지 않습니다. 아무것도 체크하지 않으면 원래 설정으로 돌아갑니다.",
    },
})
