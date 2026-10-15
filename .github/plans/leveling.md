# Plan : module de leveling (CorpUI [Leveling])

Demande du 15/10/2026 : un nouveau module pour monter de niveau, inspiré de
[factoruide](https://github.com/brouznouf/factoruide) et de RestedXP, adapté à WoW Forever.

## 1. Ce que font les deux références

**Factoruide** (code MIT ; données de quêtes en GPL-2.0, avec une part Questie « tous droits réservés ») :
- Une application de bureau (Rust) simule la partie et calcule la route la plus rapide pour un personnage. Elle installe elle-même son addon et écrit les routes dans `AddOns\Factoruide\Routes.lua`.
- Chaque étape porte : type (prendre, objectif, rendre, vol, point de vol, entraîneur, pierre de foyer, auberge, farm, donjon), quête, carte, x/y, PNJ ou objet, et niveau prévu.
- Côté jeu, l'addon offre :
  - une fenêtre « À faire / Ensuite / À prendre » qui avance toute seule (quête prise, objectif fait, quête rendue, vol, niveau atteint) ;
  - une grosse flèche qui tourne avec le personnage (verte devant, rouge derrière, distance dessous) et le repère natif de Blizzard (`C_Map.SetUserWaypoint` + `C_SuperTrack`) ;
  - une macro de ciblage, un bouton d'objet de quête avec raccourci, et le vol pris tout seul vers la destination de l'étape ;
  - les prochaines étapes numérotées sur la carte, et le temps par niveau comparé au temps prévu ;
  - l'entraîneur (seulement les sorts utiles), le marchand, l'équipement (récompense prévue, améliorations), les talents conseillés ;
  - la progression du groupe, et des alertes (cible élite ou trop haute, vie basse).

**RestedXP** (addon gratuit, guides payants ; version Forever qui couvre les niveaux 1 à 35 au 09/10/2026) :
- Guides écrits à la main par des speedrunners, étape par étape.
- Flèche réglable, et quêtes prises et rendues automatiquement.
- Macro de ciblage avec marques de raid, et bouton d'objet.
- Suivi du temps de leveling, et nettoyage des quêtes hors guide.
- Guide des talents, et achats en lot.

Leurs guides sont payants et protégés : on n'en reprend rien.

## 2. Ce que CorpUI a déjà (le module Leveling s'y branche au lieu de le refaire)

| Besoin | Module existant |
| --- | --- |
| Prendre et rendre les quêtes automatiquement (Maj = pause) | Experience (`db.autoQuest`) |
| XP/heure, temps estimé, temps à ce niveau | Experience |
| Suivi des quêtes et de leurs objectifs | Quetes |
| Sorts à venir et leur niveau | Sorts (SpellsAhead) |
| Talents : import, export, guide | Talents |
| Vendre les gris, réparer, racheter les réactifs | Marchand |
| Points de vol de chaque faction sur la carte du monde | Minicarte (Vols.lua) |

## 3. Le nœud : d'où viennent les étapes ?

Ce que le client Forever donne lui-même (lu dans la source `forever` de Blizzard) :
- `C_QuestLog.GetQuestsOnMap`, `GetNextWaypoint` et `ReadyForTurnIn` donnent où faire et où rendre chaque quête du journal, y compris quand c'est dans une autre zone ;
- `C_QuestLine.GetAvailableQuestLines(mapID)` donne les quêtes disponibles avec leur position. La carte du monde de Forever charge `QuestOfferDataProvider`, celui qui affiche les « ! » ; reste à vérifier en jeu que les quêtes classiques y figurent ;
- `C_Map.SetUserWaypoint`, `C_SuperTrack.SetSuperTrackedUserWaypoint` (flèche de navigation de Blizzard), `GetPlayerFacing` et `C_Map.GetWorldPosFromMapPos` permettent la flèche. Ils sont tous permis à un addon (« AllowedWhenUntainted » : seuls des arguments secrets les bloqueraient).

Trois sources possibles :

**A. Navigateur dynamique, sans base de données (recommandé pour la v1)**
- Le module choisit la prochaine action à partir de ce que le jeu sait :
  - rendre une quête prête ;
  - faire l'objectif le plus proche ;
  - prendre une quête disponible tout près ;
  - partir vers une autre zone.
- Il pèse la distance, l'XP de la récompense et la couleur de la quête.
- Ça marche à tout niveau et dans toute zone, nouvelles quêtes de Forever comprises.
- Aucune donnée tierce, donc aucun problème de licence.
- Limite : ce n'est pas une route optimisée sur toute la partie. Ça pilote de proche en proche.

**B. Pont avec Factoruide**
- Si l'addon Factoruide est installé et chargé, CorpUI lit ses routes (globale `Factoruide.Routes` et `Factoruide.Assignments`) et les affiche à sa façon.
- Inconvénients : il faut leur application et leur addon (deux fenêtres à l'écran), et ça dépend d'un format qui peut changer.

**C. Guides écrits, importés par copier-coller**
- Un format texte CorpUI, comme les chaînes de talents.
- Inconvénient : il faut écrire les guides. On ne peut pas en fournir de prêts. Les guides RestedXP sont payants, Questie est « tous droits réservés », et les données factoruide sont en GPL, incompatible avec CorpUI qui n'a pas de licence.

Le moteur sera bâti autour d'une « étape » générique (prendre, objectif, rendre, aller à, vol, entraîneur, foyer, farmer). B et C pourront donc s'y brancher plus tard sans tout refaire.

## 4. Contenu de la v1 (addon `CorpUI_Leveling`, famille outils, vert)

1. **Fenêtre Leveling** au style CorpUI, déplaçable avec les poignées communes.
   - Elle montre l'étape en cours et les 3 à 5 suivantes : icône par type, texte, distance.
   - Clic gauche : pointer la flèche sur la ligne. Clic droit : ignorer l'étape.
   - Bouton pour la replier.
2. **Flèche** à nous (texture du jeu ou Nano Banana) : couleur du vert au rouge, distance, coche à l'arrivée, « ailleurs » sur un autre continent.
   - En option, le repère de Blizzard, qui met une épingle sur la carte et sa propre flèche de navigation.
3. **Avancement automatique** :
   - événements du journal (`QUEST_ACCEPTED`, `QUEST_LOG_UPDATE`, `QUEST_TURNED_IN`) ;
   - montée de niveau ;
   - changement de zone ;
   - arrivée sur place.
4. **Quêtes à prendre** autour de soi, si le client les donne (point 3).
5. **Repères sur la carte du monde** : les prochaines étapes numérotées, sur un calque comme celui des points de vol.
6. **Rythme** : temps passé à chaque niveau, gardé par personnage, et comparé au meilleur de tes autres personnages. Experience compte déjà le temps au niveau en cours.
7. **Entraîneur** : une étape « aller à l'entraîneur » quand de nouveaux sorts sont disponibles (données de Sorts). En option, apprendre tout ce qui est abordable, désactivée par défaut, Maj = pause.
8. **Vol** : en option, à l'ouverture d'un maître de vol, prendre tout seul le vol vers le point le plus proche de l'étape (Maj = choisir soi-même).
9. **Nettoyage** : signaler les quêtes devenues grises (sans XP) dans le journal. On n'abandonne jamais rien sans confirmation.

Plus tard (v2), selon tes retours :
- bouton d'objet de quête sécurisé avec raccourci ;
- macro de ciblage (le nom du monstre est tiré du texte de l'objectif, qui dépend de la langue) ;
- alertes élite ou cible trop haute ;
- import de guides (C) ;
- pont Factoruide (B).

## 5. Contraintes Forever respectées

- **Taint** :
  - aucun crochet sur Blizzard et aucune écriture dans ses globales ;
  - cadres à nous, calque de carte rattaché à `WorldMapFrame.ScrollContainer.Child`, comme Vols.lua ;
  - jamais d'ouverture du journal ni de la carte par le code (le module Quetes a montré que ça les marque).
- **Valeurs secrètes** :
  - `pcall` et `issecretvalue` sur toute lecture (position, niveau et vie de la cible) ;
  - rien ne doit dépendre de la vie ou des auras en combat.
- **Cadres protégés** : la fenêtre n'est accrochée à aucun bouton sécurisé. Le bouton d'objet de la v2 sera posé hors combat seulement.
- **`RegisterEvent`** : les inscriptions passent par `pcall` (un événement inconnu interrompt le fichier).
- **Coût** : le calcul de la prochaine action et la flèche tournent sur le planificateur du noyau (`ns.Every`), à cadence raisonnable, et s'arrêtent quand le module est coupé.

## 6. Intégration au découpage

- Dossier `CorpUI_Leveling/` contenant :
  - `CorpUI_Leveling.toc` : `Dependencies: CorpUI`, `Group: CorpUI`, `OptionalDeps` = les addons précédents, `IconTexture`, titre « CorpUI [Leveling] » en vert ;
  - `Leveling/Strings.lua` (10 langues) ;
  - les fichiers du moteur.
- Entrée dans `ADDON_OF` (Core.lua) et dans `LIST` (Modules.lua), commande `/corp leveling`, et panneau d'options.
- Bancs fengari : choix de l'action, avancement, angle de la flèche. On vérifie aussi « seul » et « tous sauf un », comme pour le découpage.
- `liens.ps1` pour la jonction, puis **redémarrage complet du jeu** (nouveau dossier d'addon).
- Release : patch 2.0.1.

## 7. Livraison par étapes

1. Socle : addon, fenêtre, moteur d'étapes, source A (journal), flèche, avancement. Test en jeu.
2. Quêtes à prendre, repères sur la carte, vol, repère de Blizzard. Test en jeu.
3. Rythme par niveau, entraîneur, nettoyage. Test en jeu, puis release.

## 8. Décisions et avancement

**Choix de l'utilisateur (15/10)** :
- source : navigateur dynamique (A) ;
- nom : **Leveling** (`CorpUI_Leveling`, `/corp leveling`, alias `/corp lvl`) ;
- flèche : les deux. La flèche CorpUI est allumée par défaut. Le repère de Blizzard est une option **coupée par défaut** : ses gestionnaires d'événements (`SUPER_TRACKING_CHANGED`…) tourneraient depuis notre appel, donc il faut l'essayer en jeu avant de l'allumer d'office ;
- « ! » de la carte : on ne sait pas encore si les quêtes classiques y figurent. `/corp leveling diag` le dira au premier test (« N à prendre »).

**Étape 1 faite (15/10, à tester en jeu)** :
- fichiers : `Leveling/Moteur.lua` (choix des étapes), `Leveling/Fleche.lua` (flèche et repère), `Leveling/Leveling.lua` (fenêtre, réglages, événements), et la texture `Media/fleche.tga`, dessinée par un script et non par Nano Banana ;
- branchements : `ADDON_OF`, `PAGES` (outils), `LIST` (page Modules), et `Profils` (`leveling.ignored` reste par personnage) ;
- banc fengari `t_leveling.lua` : ordre des étapes, maintien de l'étape en cours, flèche (angle, couleur, arrivée), choix à la main, étapes ignorées, quêtes grises, valeurs secrètes, niveau maximum, réglages, déverrouillage.

**Quêtes à prendre (15/10)** :
- Le diagnostic en jeu sur l'Île de Zéphras (carte 2521) donne 0 partout : lignes de quêtes, quêtes forcées, tâches, pôles et débuts de quête. Le client Forever ne donne pas les quêtes disponibles, et la carte (M) n'affiche aucun « ! ».
- Choix de l'utilisateur : reprendre la base d'AllTheThings, version compilée pour Forever (`db/Camelot/Categories/Zones|Instances|Professions.lua`, licence MIT).
- Le script `.github/scripts/att_quetes.js` la **lit sans l'exécuter** (luaparse) et génère `Leveling/Donnees.lua` : 3 116 quêtes sur 47 cartes, 83 Ko, décodées carte par carte à la demande.
- L'avis MIT est gardé en tête de `Donnees.lua`, et seulement là : c'est la seule condition de la licence. L'utilisateur ne veut ni crédit dans le README ni mention visible.
- Filtres appliqués en jeu : camp, race, classe, niveau minimum, quêtes préalables (toutes, ou le nombre requis), quêtes exclusives, réputation, version du jeu (ajout et retrait, 1.60.1 = 16001), et quêtes déjà rendues (`GetAllCompletedQuestIDs`).
- Les titres viennent du jeu (`RequestLoadQuestByID`) ; en attendant, la ligne affiche « Quête n° X ».

## 9. Guide pas à pas (demande du 15/10)

> « un guide à suivre pas à pas qui optimise le level up, un peu comme RestedXP »

**But** : une liste d'étapes numérotées (prendre, faire, rendre, aller à, entraîneur, pierre de foyer…). L'étape en cours est en tête, avec la flèche ; elle se coche toute seule une fois faite. L'ordre suit une **route planifiée** pour limiter les trajets, et non plus « la plus proche à chaque instant ».

**Données disponibles :**
- AllTheThings : donneurs et positions (déjà intégrés), **1 907 objectifs avec position**, monstres d'objectif, quêtes préalables et suites de chaînes, niveau minimum, camp, race et classe.
- Le jeu, une fois la quête prise : position exacte des objectifs et du PNJ de rendu, XP de la récompense, couleur de difficulté.

**Approche recommandée : planificateur CorpUI en jeu**
1. **Zone** : celle où tu es, tant qu'elle a des quêtes non grises. Sinon, la suivante d'après les niveaux de la base pour ton camp.
2. **Pôles** : les donneurs proches les uns des autres (moins de 50 m environ) sont regroupés.
3. **Tournée** :
   - au pôle, prendre toutes les quêtes disponibles (et les suites débloquées sur place) ;
   - faire les objectifs dans l'ordre d'une tournée (plus proche voisin, puis amélioration 2-opt contre les allers-retours), en groupant les objectifs proches ;
   - revenir rendre au pôle ;
   - passer au pôle suivant, le plus rentable (quêtes ÷ distance).
4. **Route stable** : elle n'est recalculée que si une étape est faite, si une quête apparaît ou disparaît, ou si tu t'écartes nettement du plan.
5. **Affichage** : au dessin du suivi des quêtes, avec numéros et coches (étapes faites en gris), l'étape en cours en surbrillance, et « sauter l'étape » au clic droit.

**Limites :**
- Ce n'est ni une route de speedrunner, ni la simulation complète de factoruide (XP fine, puissance du personnage).
- Une quête sans position d'objectif dans la base n'est placée qu'une fois prise : c'est le jeu qui donne alors la position.

**Autres sources possibles :** les routes de l'appli factoruide (optimisation globale de 1 à 60, mais il faut leur appli et leur addon), ou des guides écrits à la main.

**Choix du 15/10** : planificateur CorpUI ; en plus des quêtes : entraîneur de classe, changement de zone, pierre de foyer et vols. Pas de rythme de niveau.

**Livraison 1 (15/10, à tester en jeu)** :
- `Leveling/Route.lua` : rassemble les étapes de la zone (journal, quêtes à prendre de la base, suites de chaînes prévues), puis construit la tournée :
  - plus proche voisin ;
  - amélioration par différence (n² par passe) ;
  - au pôle, tout prendre d'un coup (donneurs à moins de 40 m).
- Route stable et gardée par personnage (`leveling.route`) : une étape faite passe dans l'historique, une nouvelle s'insère à sa meilleure place.
- Recalcul : changement de zone (après 20 s) ou `/corp leveling route`.
- Données : positions des objectifs (`qo`) ajoutées à `Donnees.lua` (99 Ko).
- Fenêtre : étapes numérotées, deux dernières faites cochées en grise, clic droit = ignorer la quête.
- Banc `t_leveling` : 85 vérifications. Sur les vraies données de Zéphras : 72 étapes, 179 ms sous fengari (bien moins en jeu), 12 ms par mise à jour.

**Livraison 2 (à faire)** : changement de zone, entraîneur de classe, pierre de foyer et vols.
