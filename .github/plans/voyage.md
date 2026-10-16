# Plan : module Voyage (trajet le plus rapide)

Demande du 16/10/2026 : reprendre dans CorpUI, sous le nom « Voyage », les fonctions de shortest-path-forever (cjber, GPL-3.0).

**Règle** : ni leur code ni leurs fichiers de données. Le code est écrit pour CorpUI. Les données sont prises à la source :
- les tables du jeu Forever (DB2, produit `wowf` sur wago.tools) ;
- ce que CorpUI relève lui-même en jeu.

## Choix de l'utilisateur (16/10)

- **Fonctions** : toutes.
  - Trajet et guidage.
  - Horaires des bateaux.
  - Boussole et route vers le corps.
  - Services proches.
- **Marche** : l'utilisateur voulait les chemins réels. Faute de données de terrain libres, ce sera **en ligne droite** pour commencer. Plus tard, on pourra extraire le terrain du client de l'utilisateur.
- **Destination** :
  - Maj + clic sur la carte du monde et sur la minicarte ;
  - l'étape du Leveling quand elle est loin ;
  - une quête du suivi.
- **Affichage** : une fenêtre à part.

## Données

| Donnée | Source |
| --- | --- |
| Points de vol : position, continent, faction | table `TaxiNodes` |
| Liaisons de vol et leur prix | table `TaxiPath` |
| Tracé des vols (longueur, donc durée estimée ; ligne sur la carte) | table `TaxiPathNode` |
| Bateaux, zeppelins, tram : tracés et quais (arrêts) | `TaxiPathNode` (chemins des transports, arrêts avec délai) |
| Ascenseurs : cycle | `TransportAnimation` |
| Points de vol connus | jeu : `C_TaxiMap.GetTaxiNodesForMap` |
| Durée réelle des vols, horaires des bateaux | relevés en jeu par CorpUI |
| Pierre de foyer : lieu de liaison | relevé au moment où tu la lies |
| Portails et téléportations (destinations, côté serveur) | les quelques capitales, notées à la main |
| Services proches (PNJ) | base AllTheThings (MIT, comme pour le Leveling) |

## Livraisons

1. Données des vols, planificateur (marche en ligne droite, vols, pierre de foyer), fenêtre des étapes, flèche, destinations (Maj + clic sur la carte du monde, étape du Leveling, quête).
2. Bateaux, zeppelins, tram, ascenseurs, portails ; horaires estimés, puis relevés en jeu (compte à rebours, alerte à l'arrivée).
3. Ligne du trajet sur les deux cartes, Maj + clic sur la minicarte, boussole, route vers le corps.
4. Services proches.
5. Plus tard, si besoin : vrais chemins à pied (terrain extrait du client).

## Avancement

**Livraison 1 (16/10, à tester en jeu)** :
- `Voyage/Donnees.lua` est généré par `.github/scripts/voyage_donnees.js` à partir des tables `wowf` 1.60.1.70245 : 91 points de vol, 304 vols, 5 lignes de bateau avec leurs quais.
- `Planif.lua` : plus court chemin (Dijkstra) entre le départ, l'arrivée, les points de vol connus de ton camp, les quais et le lieu de la pierre de foyer.
  - Marche : en ligne droite, à ta vitesse (celle de ta monture, relevée en jeu).
  - Vol : durée relevée en jeu, sinon longueur du tracé ÷ vitesse de vol (apprise en volant, 32 m/s au départ).
  - Bateau : attente moyenne d'une demi-rotation, estimée (30 m/s, arrêts des tables).
  - Pierre de foyer : 15 s, plus la recharge restante.
  - Les vols qui se suivent font une seule étape (« par » les escales).
- `Releves.lua` : noms et points de vol connus (carte du jeu, maître de vol ouvert), vols chronométrés, lieu de la pierre (liée chez l'aubergiste ou utilisée), vitesse sur monture, position d'une quête.
- `Voyage.lua` :
  - fenêtre des étapes, au dessin du suivi des quêtes ;
  - passage à l'étape suivante au bout de chaque étape ;
  - recalcul toutes les 10 s en marchant, jamais en vol ;
  - suivi de l'étape du Leveling quand un trajet plus rapide que la marche existe ;
  - « Y aller » dans le menu du suivi des quêtes (`ns.QuestMenuHooks`, lu par `Quetes.lua`).
- `Fleche.lua` : flèche du voyage. Celle du Leveling se cache pendant un voyage.
- `Carte.lua` : Maj + clic sur la carte du monde (destination), Maj + clic droit (annuler), étoile sur la destination.
- Banc `t_voyage` : 62 vérifications.
- Les bateaux sont pris dès cette livraison, avec une attente estimée. Reste à vérifier en jeu que les 5 lignes des tables existent bien.

## Marche sur le terrain (demande du 16/10 : plus de ligne droite)

**Choix de l'utilisateur** : lire le terrain du jeu (« Terrain du jeu », plutôt que des cols appris en jeu). Il a aussi demandé de ne pas oublier le tram des profondeurs.

**Outils** (`.github/scripts/terrain`, écrits pour CorpUI, sans dépendance, lecture locale du jeu installé, rien de téléchargé) :
- `casc.js` : lecture du stockage du jeu (index, archives, BLTE, encodage, racine) ;
- `adt.js` : cartes (WDT) et tuiles de terrain (hauteurs, trous, eau) ;
- `wmo.js` : bâtiments, ponts, tunnels, villes (triangles de collision, placement) ;
- `voxel.js` : colonnes de 1 m, surfaces praticables (pente de 50° au plus, 2,2 m de place au-dessus), passages d'une colonne à l'autre (marche de 1,8 m, chute de 12 m au plus) ;
- `liquides.js` : nature des eaux (table LiquidType : mer, eau douce, lave et vase) ;
- `graphe.js` : réseau de marche d'un continent ; `export.js` : fichier `Voyage/Chemins.lua` ;
- `apercu.js`, `praticable.js`, `chemin.js`, `ensembles.js` : images et contrôles.

**Réseau** :
- dans chaque bloc, les surfaces reliées forment une « pièce » (un point du réseau) ;
- la nage n'est gardée qu'à moins de deux blocs d'une terre ;
- on ne garde que les grands ensembles reliés dans les deux sens qui contiennent un point de vol, un quai ou une entrée de liaison (les sommets inaccessibles disparaissent) ;
- les distances à pied entre ces points sont calculées une fois pour toutes.

**Liaisons** (tables du jeu) :
- tram des profondeurs : déclencheurs 2173 (Hurlevent) et 2175 (Forgefer) ; 130 s (animation : 54 s de trajet, cycle de 143 s) ;
- portail Rut'theran (542) ↔ Darnassus (527) : 5 s.

**Dans l'addon** :
- `Marche.lua` : décodage, pièce la plus proche, Dijkstra et A* en tâche de fond (budget de 6 ms par image) ;
- le planificateur reçoit le coût de chaque marche ;
- la flèche suit les points de passage ; la fenêtre affiche les zones traversées.

**Taille des blocs** : 133 m (`BLOC=128`). À 67 m, les données pesaient 1,7 Mo pour des chemins à peine meilleurs (1 à 4 %). À 133 m : 16 011 pièces (Royaumes de l'Est), 18 642 (Kalimdor), 671 (Île de Zephras), 687 Ko en tout.

**Refaire les données** (Git Bash, depuis `.github/scripts/terrain`, CSV de LiquidType sur wago.tools) :
```
for m in Azeroth Kalimdor Zephras; do BLOC=128 node --max-old-space-size=12000 graphe.js "D:/Games/World of Warcraft" wow_classic_beta $m /tmp/$m.json /tmp/LiquidType.csv; done
node export.js ../../../CorpUI_Voyage/Voyage/Chemins.lua /tmp/Azeroth.json /tmp/Kalimdor.json /tmp/Zephras.json
```

**Bancs** : `t_voyage` (72 vérifications), `t_marche` (14, sur les vraies données).

**Restent** :
- les ascenseurs (Fossoyeuse, Les Pitons-du-Tonnerre) : positions côté serveur, à relever en jeu ;
- les portes fermées (grille de la Gorge des Vents brûlants) : absentes des données ; une liste de passages interdits, à compléter en jouant.
