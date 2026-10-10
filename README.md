<div align="center">

<img src=".github/logo.png" alt="Logo CorpUI" width="128">

# CorpUI

**Une interface complète et modulaire pour WoWForever.**

Cadres, barres d'action, chat, sacs, hôtel des ventes, outils de groupe et de raid : tout se règle dans une seule fenêtre, `/corp`.

![WoWForever](https://img.shields.io/badge/WoWForever-d65cff?style=for-the-badge)
![Interface](https://img.shields.io/badge/Interface-16001-ffd100?style=for-the-badge)
![Langues](https://img.shields.io/badge/Langues-10-5b8def?style=for-the-badge)
[![Version](https://img.shields.io/github/v/release/Cerynna/CorpUI?style=for-the-badge&label=Version&color=3fb950)](https://github.com/Cerynna/CorpUI/releases/latest)

[Modules](#ce-quil-contient) · [Installation](#installation) · [Commandes](#commandes) · [Apparence](#apparence) · [Pensé pour WoWForever](#pensé-pour-wowforever) · [Crédits](#crédits)

</div>

---

## Présentation

CorpUI remplace l'interface du jeu par un ensemble de modules cohérents, du cadre du joueur jusqu'à l'hôtel des ventes. Chaque module s'active ou se coupe à part, se règle dans la même fenêtre et suit le profil du personnage.

- **Une seule fenêtre de réglages** : une colonne de pages (Interface, Groupe et raid, Outils), une recherche dans toutes les options, un aperçu en direct des cadres pendant qu'on les règle.
- **Une apparence plate et sobre** : fonds neutres, liserés fins, accent à la couleur de la classe, avec une disposition d'écran prête à l'emploi.
- **Profils** par personnage, copie et partage par texte.
- **10 langues** : français, anglais, allemand, espagnol, portugais, italien, russe, chinois simplifié et traditionnel, coréen.
- **Assistant d'installation** au premier lancement.

## Ce qu'il contient

### Interface

| Module | Ce qu'il fait | Commande |
| --- | --- | --- |
| **Cadres d'unité** | Joueur, cible, cible de la cible, focalisation, familier, boss, arène ; barres de sort, auras, ressources, totems actifs du chaman, minuteur de coups blancs. Un seul éditeur pour tous les cadres. | `/corp cadres` |
| **Groupe et raid** | Cadres de groupe et de raid à nous : débuffs, dissipation, soins entrants, aggro, réglages pour les soigneurs. | `/corp groupe` |
| **Barres d'action** | Neuf barres, barre du familier, barre des totems, bouton de sortie de véhicule ; taille, espacement, fond, visibilité par condition, fondu au survol ou hors combat, raccourcis rapides façon ElvUI. | `/corp barres` |
| **Menus** | Barre des postures et formes, micro-menu et barre des sacs, réglables comme les barres d'action. | `/corp menus` |
| **Barres de sort** | Barres d'incantation du joueur, de la cible et de la focalisation ; sort non interruptible, interruption prête. | `/corp incantations` |
| **Auras** | Buffs et débuffs du joueur et de la cible, filtres par listes. | `/corp auras` |
| **Expérience** | Barre d'XP : quêtes, repos, XP par heure, temps avant le niveau. | `/corp xp` |
| **Minicarte** | Minicarte carrée avec zone, coordonnées et heure ; icônes rangées dans une boîte. | `/corp minicarte` |
| **Barres d'infos** | Jusqu'à dix bandeaux : or, sacs, durabilité, FPS, latence, heure, coordonnées, amis, guilde. | `/corp infos` |
| **Suivi de quêtes** | Quêtes suivies et leurs objectifs, couleur de difficulté, progression du groupe dans l'infobulle, menu au clic droit. | `/corp quetes` |
| **Plaques de nom** | Plaques des unités : sort en cours, tes débuffs, points de combo, cible actuelle. | `/corp plaques` |
| **Infobulles** | Infobulles au style CorpUI, prix de l'hôtel des ventes et objets possédés par tes personnages. | `/corp infobulles` |
| **Chat** | Fenêtres de discussion au style CorpUI : onglets détachés, colonne d'icônes, champ de saisie encadré, onglets par défaut, historique, copie du texte et des liens. | `/corp chat` |
| **Compteur** | Fenêtres façon Details : dégâts, soins, absorptions, interruptions, dissipations, morts, et la menace du groupe sur ta cible avec alerte avant l'aggro. | `/corp compteur` |
| **Sacs** | Tous les sacs en un seul, recherche et tri ; banque. | `/corp sacs` |
| **Butin** | Fenêtre de butin et jets de groupe (Besoin, Cupidité, Passer). | `/corp butin` |
| **Marchand** | Réparation et vente des objets gris automatiques, rachat des réactifs. | `/corp marchand` |
| **Habillage** | Les fenêtres de Blizzard au style CorpUI (fiche du personnage, grimoire, talents, journal, métiers, hôtel des ventes, courrier…), déplaçables. | `/corp habillage` |

### Groupe et raid

| Module | Ce qu'il fait | Commande |
| --- | --- | --- |
| **Buffs** | Buffs des paladins, prêtres, mages et druides : qui manque quoi, répartition par groupe, résurrections. | `/corp buffs` |
| **Dissipation** | Alerte de dissipation sur les cadres de groupe (couleur, son) et répartition des groupes du raid. | `/corp dissipation` |
| **Rappels** | Tes buffs personnels et enchantements d'arme manquants, un clic pour les lancer. | `/corp rappels` |
| **Recharges** | Suivi des temps de recharge du groupe et du raid, barre de recharges personnelle. | `/corp cd` |
| **Notes de raid** | Notes partagées avec le groupe façon MRT : éditeur, fenêtre de note, marqueurs. | `/corp note` |
| **Barre de raid** | Marqueurs de cible et au sol, appel, vérification des rôles, décompte de pull. | `/corp raid` |
| **Invitations** | Invite automatiquement les joueurs qui envoient un mot clé (`+1`). | `/corp inv` |
| **Sorts au clic** | Lancer un sort en cliquant sur un cadre CorpUI. | `/corp clics` |
| **Qui a CorpUI** | Les joueurs de ta guilde et de ton groupe qui utilisent CorpUI. | `/corp qui` |

### Outils

| Module | Ce qu'il fait | Commande |
| --- | --- | --- |
| **Persos** | Tous tes personnages : niveau, or, métiers, objets, raids verrouillés. | `/corp persos` |
| **Métiers** | File de fabrication et liste de courses façon Skillet, bénéfice par recette. | `/corp metiers` |
| **Désenchanteur** | Une icône pour désenchanter un par un les objets des sacs. | `/corp dez` |
| **Hôtel des ventes** | Scan, valeur marché et historique, aide à la vente, mes enchères, listes d'achats, bonnes affaires, façon TSM. | `/corp hv` |
| **Comptabilité** | Ventes, achats, frais de l'hôtel des ventes, or de tous les personnages. | `/corp compta` |
| **Talents** | Export et import des talents. | `/corp talents` |
| **Sorts à venir** | Les prochains sorts et le niveau pour les apprendre. | `/corp sorts` |
| **Profils** | Réglages par personnage, copie, partage. | `/corp profils` |

### Mini-jeux

| Module | Ce qu'il fait | Commande |
| --- | --- | --- |
| **Course du murloc** | Fais courir un murloc sur la plage et saute les obstacles. | `/corp murloc` |
| **Fusion des minerais** | Un 2048 de mineur : du cuivre jusqu'aux objets légendaires. | `/corp minerais` |

Les mini-jeux peuvent s'ouvrir tout seuls pendant les trajets en griffon.

## Installation

1. Ouvre la [dernière version](https://github.com/Cerynna/CorpUI/releases/latest) (rubrique **Releases** du dépôt) et télécharge **CorpUI-X.Y.Z.zip**, pas « Source code ».
2. Décompresse-le dans `World of Warcraft\_classic_beta_\Interface\AddOns\` : tu obtiens un dossier `CorpUI`.
3. Lance le jeu, active CorpUI dans la liste des addons, puis tape `/corp`.

Mise à jour : remplace le dossier `CorpUI` par celui de la nouvelle version. Tes réglages sont gardés (ils sont dans `WTF`). `/corp qui` montre la version de CorpUI des joueurs de ta guilde et de ton groupe.

> [!NOTE]
> Version en cours de développement : bouton **Code** puis **Download ZIP** (ou `git clone`), et renomme le dossier en **`CorpUI`** (le ZIP de GitHub l'appelle `CorpUI-main`).

> [!TIP]
> Les nouvelles images, polices et sons ne sont pris en compte qu'après un redémarrage complet du jeu ; un `/reload` suffit pour le reste.

## Commandes

| Commande | Effet |
| --- | --- |
| `/corp` | Ouvre ou ferme la fenêtre de réglages. |
| `/corp <module>` | Ouvre la page d'un module, par exemple `/corp barres` ou `/corp chat`. |
| `/corp barres kb` | Mode raccourcis rapides : survoler un bouton et appuyer sur une touche. |
| `/corp lang <code>` | Change la langue de CorpUI (`frFR`, `enUS`, `deDE`…). |
| `/corp minimap` | Affiche ou cache le bouton de la minicarte. |

`/corpui` et `/cui` sont des alias de `/corp`. Le bouton **Déverrouiller** de la page Général affiche les poignées pour déplacer les cadres et les barres.

## Apparence

- Thème plat, liserés fins, fonds neutres ; la couleur d'accent se choisit dans **Général** (couleur de la classe par défaut).
- Police **Saira Semi Condensed** (repli sur la police du jeu en russe, chinois et coréen), au choix dans **Général**.
- Disposition prête à l'emploi au premier lancement ; **Profils › Réinitialiser** la remet.

## Pensé pour WoWForever

WoWForever protège beaucoup de données en combat (valeurs « secrètes ») et bloque le code des addons qui touche à l'interface de Blizzard. CorpUI est écrit en conséquence :

- aucun crochet ni remplacement de fonction de Blizzard, aucune variable globale qu'il lit ;
- les actions protégées passent par des boutons sécurisés et leurs extraits (lancer un sort, choisir un totem, ouvrir le journal de quêtes), donc elles fonctionnent aussi en combat ;
- les valeurs secrètes sont transmises telles quelles aux barres et aux textes, jamais comparées ni calculées ;
- les auras passent par le conteneur sécurisé de Blizzard (`CustomAuraContainerTemplate`).

## Publier une version

Depuis le dossier `CorpUI`, dans Git Bash : `.github/scripts/release.sh 1.2.0`. Le script met la version dans le `.toc`, commite, pose le tag `v1.2.0` et pousse. GitHub construit alors `CorpUI-1.2.0.zip` (un dossier `CorpUI` sans les fichiers de développement) et publie la release, avec la liste des changements depuis la version précédente.

## Crédits

- **Polices** : [Saira](https://github.com/Omnibus-Type/Saira) et [Archivo Black](https://github.com/Omnibus-Type/ArchivoBlack) (Omnibus-Type), [Roboto](https://fonts.google.com/specimen/Roboto) (Google), toutes sous licence SIL Open Font License 1.1 (fichiers `OFL.txt` dans `Media`).
- **Sons** : Kenney et Robin Lamb (CC0), Joe Lamb et dobroide (CC BY 3.0), AntumDeluge (CC0). Détail dans [`Media/Sons/CREDITS.txt`](Media/Sons/CREDITS.txt).
- **Images** des mini-jeux et icônes : générées pour CorpUI avec Nano Banana Pro. Détail dans [`Media/Jeux/CREDITS.txt`](Media/Jeux/CREDITS.txt).
- **Inspirations** : ElvUI, Details!, TradeSkillMaster, Method Raid Tools, Skillet et NaowhForever, pour les idées ; le code de CorpUI est écrit pour lui.

---

## Licence

Aucune licence n'est publiée pour l'instant : le code de CorpUI reste la propriété de son auteur. Les polices, sons et images gardent leurs licences propres, indiquées dans les crédits.
