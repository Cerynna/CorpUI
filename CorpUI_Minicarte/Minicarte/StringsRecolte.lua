local _, ns = ...
if CorpUI and next(ns) == nil then ns = CorpUI end   -- espace de noms du noyau (addon CorpUI)
-- Textes des icones de recolte sur la minicarte (Recolte.lua), 10 langues.
ns.AddStrings({
    enUS = {
        MAP_H_NODES = "Herbs, ore and chests on the minimap",
        MAP_OPT_NODES = "Show the herb, ore or chest icon instead of the yellow dot",
        MAP_NODES_SIZE = "Icon size: %d",
        MAP_NODES_DIAG = "minimap nodes: tracking %s, %d nodes found (%d shown), %d herb names, %d metals",
    },
    frFR = {
        MAP_H_NODES = "Plantes, minerais et coffres sur la minicarte",
        MAP_OPT_NODES = "Icône de la plante, du minerai ou du coffre à la place du point jaune",
        MAP_NODES_SIZE = "Taille des icônes : %d",
        MAP_NODES_DIAG = "récolte sur la minicarte : recherche %s, %d nœuds trouvés (%d affichés), %d noms de plantes, %d métaux",
    },
    deDE = {
        MAP_H_NODES = "Kräuter, Erze und Truhen auf der Minikarte",
        MAP_OPT_NODES = "Symbol des Krauts, Erzes oder der Truhe statt des gelben Punkts",
        MAP_NODES_SIZE = "Symbolgröße: %d",
        MAP_NODES_DIAG = "Minikarte: Suche %s, %d Vorkommen gefunden (%d angezeigt), %d Kräuternamen, %d Metalle",
    },
    esES = {
        MAP_H_NODES = "Hierbas, minerales y cofres en el minimapa",
        MAP_OPT_NODES = "Icono de la hierba, el mineral o el cofre en lugar del punto amarillo",
        MAP_NODES_SIZE = "Tamaño de los iconos: %d",
        MAP_NODES_DIAG = "minimapa: búsqueda %s, %d nodos encontrados (%d mostrados), %d nombres de hierbas, %d metales",
    },
    ptBR = {
        MAP_H_NODES = "Ervas, minérios e baús no minimapa",
        MAP_OPT_NODES = "Ícone da erva, do minério ou do baú no lugar do ponto amarelo",
        MAP_NODES_SIZE = "Tamanho dos ícones: %d",
        MAP_NODES_DIAG = "minimapa: rastreamento %s, %d nós encontrados (%d mostrados), %d nomes de ervas, %d metais",
    },
    itIT = {
        MAP_H_NODES = "Erbe, minerali e forzieri sulla minimappa",
        MAP_OPT_NODES = "Icona dell'erba, del minerale o del forziere al posto del punto giallo",
        MAP_NODES_SIZE = "Dimensione delle icone: %d",
        MAP_NODES_DIAG = "minimappa: ricerca %s, %d nodi trovati (%d mostrati), %d nomi di erbe, %d metalli",
    },
    ruRU = {
        MAP_H_NODES = "Травы, руда и сундуки на миникарте",
        MAP_OPT_NODES = "Значок травы, руды или сундука вместо жёлтой точки",
        MAP_NODES_SIZE = "Размер значков: %d",
        MAP_NODES_DIAG = "миникарта: поиск %s, найдено %d (показано %d), названий трав %d, металлов %d",
    },
    zhCN = {
        MAP_H_NODES = "小地图上的草药、矿石和宝箱",
        MAP_OPT_NODES = "用草药、矿石或宝箱的图标代替黄点",
        MAP_NODES_SIZE = "图标大小：%d",
        MAP_NODES_DIAG = "小地图采集：追踪 %s，找到 %d 个（显示 %d 个），草药名称 %d 个，金属 %d 种",
    },
    zhTW = {
        MAP_H_NODES = "小地圖上的草藥、礦石和寶箱",
        MAP_OPT_NODES = "用草藥、礦石或寶箱的圖示代替黃點",
        MAP_NODES_SIZE = "圖示大小：%d",
        MAP_NODES_DIAG = "小地圖採集：追蹤 %s，找到 %d 個（顯示 %d 個），草藥名稱 %d 個，金屬 %d 種",
    },
    koKR = {
        MAP_H_NODES = "미니맵의 약초, 광석, 상자",
        MAP_OPT_NODES = "노란 점 대신 약초, 광석 또는 상자 아이콘",
        MAP_NODES_SIZE = "아이콘 크기: %d",
        MAP_NODES_DIAG = "미니맵 채집: 추적 %s, %d개 발견 (%d개 표시), 약초 이름 %d개, 금속 %d종",
    },
})
