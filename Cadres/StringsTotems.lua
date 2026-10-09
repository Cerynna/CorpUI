local _, ns = ...

-- Textes des totems actifs du chaman (Cadres\Totems.lua)
ns.AddStrings({
    enUS = {
        TOTEM_MOVER = "Totems", TOTEM_HEADER = "Active totems (shaman)",
        TOTEM_OPT_ENABLE = "Show active totems", TOTEM_OPT_ATTACH = "Under the player frame",
        TOTEM_OPT_EMPTY = "Show empty slots", TOTEM_OPT_TIME = "Time left", TOTEM_SIZE = "Size: %d",
        TOTEM_HINT = "Earth, Fire, Water, Air. Right-click a totem to destroy it. Unchecking \"Under the player frame\" lets you move it (unlock the interface).",
    },
    frFR = {
        TOTEM_MOVER = "Totems", TOTEM_HEADER = "Totems actifs (chaman)",
        TOTEM_OPT_ENABLE = "Afficher les totems actifs", TOTEM_OPT_ATTACH = "Sous le cadre joueur",
        TOTEM_OPT_EMPTY = "Montrer les cases vides", TOTEM_OPT_TIME = "Temps restant", TOTEM_SIZE = "Taille : %d",
        TOTEM_HINT = "Terre, Feu, Eau, Air. Clic droit sur un totem : le détruire. « Sous le cadre joueur » décoché : déplaçable (déverrouiller l'interface).",
    },
    deDE = {
        TOTEM_MOVER = "Totems", TOTEM_HEADER = "Aktive Totems (Schamane)",
        TOTEM_OPT_ENABLE = "Aktive Totems anzeigen", TOTEM_OPT_ATTACH = "Unter dem Spielerrahmen",
        TOTEM_OPT_EMPTY = "Leere Plätze zeigen", TOTEM_OPT_TIME = "Restzeit", TOTEM_SIZE = "Größe: %d",
        TOTEM_HINT = "Erde, Feuer, Wasser, Luft. Rechtsklick auf ein Totem: zerstören. Ohne „Unter dem Spielerrahmen“ verschiebbar (Oberfläche entsperren).",
    },
    esES = {
        TOTEM_MOVER = "Tótems", TOTEM_HEADER = "Tótems activos (chamán)",
        TOTEM_OPT_ENABLE = "Mostrar los tótems activos", TOTEM_OPT_ATTACH = "Bajo el marco del jugador",
        TOTEM_OPT_EMPTY = "Mostrar casillas vacías", TOTEM_OPT_TIME = "Tiempo restante", TOTEM_SIZE = "Tamaño: %d",
        TOTEM_HINT = "Tierra, Fuego, Agua, Aire. Clic derecho en un tótem: destruirlo. Sin «Bajo el marco del jugador» se puede mover (desbloquear la interfaz).",
    },
    ptBR = {
        TOTEM_MOVER = "Totens", TOTEM_HEADER = "Totens ativos (xamã)",
        TOTEM_OPT_ENABLE = "Mostrar os totens ativos", TOTEM_OPT_ATTACH = "Sob o quadro do jogador",
        TOTEM_OPT_EMPTY = "Mostrar espaços vazios", TOTEM_OPT_TIME = "Tempo restante", TOTEM_SIZE = "Tamanho: %d",
        TOTEM_HINT = "Terra, Fogo, Água, Ar. Clique direito num totem: destruí-lo. Sem \"Sob o quadro do jogador\" pode ser movido (desbloquear a interface).",
    },
    itIT = {
        TOTEM_MOVER = "Totem", TOTEM_HEADER = "Totem attivi (sciamano)",
        TOTEM_OPT_ENABLE = "Mostra i totem attivi", TOTEM_OPT_ATTACH = "Sotto il riquadro del giocatore",
        TOTEM_OPT_EMPTY = "Mostra le caselle vuote", TOTEM_OPT_TIME = "Tempo rimanente", TOTEM_SIZE = "Dimensione: %d",
        TOTEM_HINT = "Terra, Fuoco, Acqua, Aria. Clic destro su un totem: distruggerlo. Senza «Sotto il riquadro del giocatore» si può spostare (sblocca l'interfaccia).",
    },
    ruRU = {
        TOTEM_MOVER = "Тотемы", TOTEM_HEADER = "Активные тотемы (шаман)",
        TOTEM_OPT_ENABLE = "Показывать активные тотемы", TOTEM_OPT_ATTACH = "Под рамкой игрока",
        TOTEM_OPT_EMPTY = "Показывать пустые ячейки", TOTEM_OPT_TIME = "Оставшееся время", TOTEM_SIZE = "Размер: %d",
        TOTEM_HINT = "Земля, Огонь, Вода, Воздух. Правый клик по тотему: уничтожить. Без «Под рамкой игрока» можно перемещать (разблокировать интерфейс).",
    },
    zhCN = {
        TOTEM_MOVER = "图腾", TOTEM_HEADER = "当前图腾（萨满祭司）",
        TOTEM_OPT_ENABLE = "显示当前图腾", TOTEM_OPT_ATTACH = "在玩家框体下方",
        TOTEM_OPT_EMPTY = "显示空位", TOTEM_OPT_TIME = "剩余时间", TOTEM_SIZE = "大小：%d",
        TOTEM_HINT = "大地、火焰、水、空气。右键点击图腾：摧毁。取消“在玩家框体下方”后可移动（解锁界面）。",
    },
    zhTW = {
        TOTEM_MOVER = "圖騰", TOTEM_HEADER = "目前圖騰（薩滿）",
        TOTEM_OPT_ENABLE = "顯示目前圖騰", TOTEM_OPT_ATTACH = "在玩家框架下方",
        TOTEM_OPT_EMPTY = "顯示空位", TOTEM_OPT_TIME = "剩餘時間", TOTEM_SIZE = "大小：%d",
        TOTEM_HINT = "大地、火焰、水、空氣。右鍵點擊圖騰：摧毀。取消「在玩家框架下方」後可移動（解鎖介面）。",
    },
    koKR = {
        TOTEM_MOVER = "토템", TOTEM_HEADER = "활성 토템 (주술사)",
        TOTEM_OPT_ENABLE = "활성 토템 표시", TOTEM_OPT_ATTACH = "플레이어 프레임 아래",
        TOTEM_OPT_EMPTY = "빈 칸 표시", TOTEM_OPT_TIME = "남은 시간", TOTEM_SIZE = "크기: %d",
        TOTEM_HINT = "대지, 불, 물, 바람. 토템 우클릭: 파괴. \"플레이어 프레임 아래\"를 해제하면 이동 가능 (인터페이스 잠금 해제).",
    },
})
