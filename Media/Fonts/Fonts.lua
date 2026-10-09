--[[--------------------------------------------------------------------------
    CorpUI - polices connues (dossier Media\Fonts)
    Un addon ne peut pas lister un dossier : les polices sont declarees ici.
    Chemins relatifs a Media\Fonts. "regular" sert aux textes, "bold" et
    "black" aux titres. cjk = true si la police a les caracteres chinois et
    coreens (sinon le jeu garde sa police pour ces langues).

    Pour une nouvelle police, le plus simple : creer son dossier dans
    Media\Fonts, puis taper son nom dans l onglet General de CorpUI (bouton
    Ajouter) ; CorpUI cherche les fichiers habituels tout seul.
----------------------------------------------------------------------------]]

local _, ns = ...

ns.FONT_REGISTRY = {
    {
        key = "Roboto",
        regular = "Roboto\\static\\Roboto-Medium.ttf",
        bold = "Roboto\\static\\Roboto-Bold.ttf",
        black = "Roboto\\static\\Roboto-Black.ttf",
    },
}
