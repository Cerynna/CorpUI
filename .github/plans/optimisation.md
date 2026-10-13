# Plan d'optimisation de CorpUI

Branche `optimisation` (13/10/2026). Le plan s'appuie sur quatre audits du code (socle, combat, sacs et économie, habillage) : plus de 100 constats avec leurs numéros de ligne.

Chaque point coché est fait, testé hors jeu (bancs d'essai : tous les bancs donnent les mêmes résultats qu'avant) et commité. L'ensemble a été validé en jeu le 13/10.

**Règles tenues partout :**
- aucun crochet sur le code de Blizzard, aucune écriture dans ses globales ;
- tests `issecretvalue` gardés avant toute comparaison ;
- rien de sécurisé n'est montré, caché ou déplacé en combat ;
- le comportement visible reste le même, sauf correction de bug signalée.

**Mesurer :** `/corp perf` donne la mémoire de CorpUI et le temps passé par chaque tâche périodique ; `/corp perf reset` remet les compteurs à zéro.

## Lot 0 — Socle

- [x] **Textes traduits.** La langue active est mise en cache, et chaque texte est mémorisé après sa première lecture. Les 8 langues inutilisées sont retirées de la mémoire après la connexion, soit environ 1 Mo (une autre langue choisie s'applique au `/reload`).
- [x] **Planificateur commun** (`ns.Every`). Un seul cadre fait tourner toutes les tâches périodiques : une comparaison par image tant qu'aucune n'est due. Il mesure le temps de chaque tâche pour `/corp perf`.

## Lot 1 — Combat : le plus rentable (événements d'unité, barres, groupe)

- [x] **Groupe.** Chaque événement d'unité va directement au bouton de l'unité, au lieu de parcourir les 44 boutons (plusieurs centaines d'événements par seconde en raid avec les plaques).
- [x] **Groupe.** Vie, puissance, nom et niveau sont mis à jour séparément. UNIT_FLAGS ne relance plus que l'état de mort.
- [x] **Groupe.** UNIT_AURA ne construit plus de signature, remplacée par une version des réglages. Les éléments de l'ancien chemin sont cachés une seule fois.
- [x] **Groupe et Dissipation.** Rafales de GROUP_ROSTER_UPDATE regroupées. Seules les ancres sont refaites, et seulement si les sous-groupes ont changé.
- [x] **Groupe.** Alertes et portée à l'arrêt hors groupe.
- [x] **Barres.**
  - Rien si les barres CorpUI sont coupées.
  - Mise à jour partielle selon l'événement (recharge, utilisable, état).
  - Boutons cachés sautés, rattrapés à l'affichage.
  - Rafales d'une même image regroupées.
- [x] **Barres.** La couleur de portée ne change que si l'état change.
- [x] **Menace.** L'alerte lit directement la menace du joueur au lieu de collecter tout le raid 5 fois par seconde.
- [x] **Buffs.**
  - Table unité → membre pour UNIT_AURA.
  - Rien en combat (les noms y sont secrets ; un relevé est déjà prévu à la fin du combat).
- [x] **Diffusion `ns.Changed`.**
  - Les rafraîchissements internes de Buffs ne réveillent plus les 24 modules.
  - Cadres ne refait plus deux fois `updateAll`.
- [x] **Recharges.** UNIT_FLAGS et UNIT_CONNECTION : seulement les unités du groupe, et seulement si le suivi est affiché.
- [x] **Auras.**
  - UNIT_AURA inscrit pour le joueur et la cible seulement.
  - Plus de rafraîchissement complet du conteneur de la cible à chaque aura : le conteneur du client se met à jour seul.
- [x] **Plaques.**
  - Disposition refaite seulement après un changement de réglage.
  - UNIT_AURA ignoré avec le conteneur natif.
  - Le pilote ne parcourt plus toutes les plaques à chaque image.
- [x] **Ressources.**
  - Une seule mise à jour par variation de puissance (FREQUENT seul).
  - Points de combo seulement pour les classes qui en ont.
  - Étincelles à l'arrêt quand rien n'est à montrer.
- [x] **Compteur.**
  - Style des lignes seulement au changement de réglage.
  - Lectures sans fermeture.
  - Menace partagée avec Menace.
  - Pilote au repos quand rien n'est à faire.
- [x] **Cadres.**
  - Vie et puissance : valeur secrète testée d'abord, sans erreur attrapée à chaque événement.
  - Cible de la cible : relevée seulement quand elle est affichée.
- [x] **Coups, Chasseur, Éclats, Totems, Rappels, Expérience, Menus, Raid, DamageMeter.** Pilotes arrêtés quand ils n'ont rien à faire (module coupé, autre classe, rien d'affiché), et travail réduit à ce qui change.
  - Éclats, Totems et Raid tournaient déjà seulement quand ils servent : laissés tels quels.

## Lot 2 — Infobulles et barre d'infos (actives en permanence)

- [x] **Infobulles.**
  - Plus de table ni de fermeture créées à chaque image.
  - NineSlice et barre de vie mises en cache.
  - Couleur du bord : à l'affichage, puis 10 fois par seconde au lieu de chaque image ; le bandeau reprend cette couleur et n'est remis en page que si son texte ou sa place change.
  - Valeur de désenchantement mémorisée par objet (jusqu'au prochain relevé de l'HV) ; dernière vente lue dans un index au lieu de parcourir tout le registre.
- [x] **Barre d'infos.**
  - Or, sacs, durabilité, amis et guilde sur leurs événements (et toutes les 10 s par sécurité).
  - Relevé périodique seulement pour fps, latence, heure et coordonnées.
  - Mise en page seulement si un texte change.
  - Relevé de la guilde seulement si elle est affichée.
- [x] **Fondu des barres** (Core). Seules les barres en fondu sont suivies, avec `GetCursorInfo` une fois par image, et le pilote est arrêté quand aucune ne l'est.

## Lot 3 — Pilotes permanents (fenêtres fermées, modules coupés)

- [x] **`ns.ModuleOff`** arrête aussi les pilotes du module coupé (OnUpdate du cadre, tâches du planificateur inscrites pour ce module).
- [x] **Habillage.**
  - Les 19 pilotes à seuil passent sur le planificateur commun (5 ou 10 fois par seconde au lieu d'un appel à chaque image, arrêtés habillage coupé).
  - Le journal de quêtes ne refait plus sa passe de textes carte fermée (une dernière passe à la fermeture).
  - Laissés tels quels : PNJ (ses textes doivent être posés à chaque image avant le rendu), et le repeint de Skins et Communs (il ne travaille déjà que sur les fenêtres affichées).
- [x] **Hôtel des ventes, courrier, butin, métiers, SpellsAhead, talents, chat, chevrons, parent caché, icône d'erreurs, poignées, file de Comm.** Pilotes posés seulement pendant qu'ils servent.
  - Panneau, envoi et relève du courrier de l'HV, file des métiers, SpellsAhead, talents, chevrons, parent caché : planificateur commun.
  - Bouton d'achat de l'HV : rien hors de l'hôtel des ventes.
  - Déjà au repos quand ils ne servent pas : butin, poignées (seulement déverrouillé), file de Comm (cachée vide), icône d'erreurs (un test par image, seulement si des erreurs existent).

## Lot 4 — Sacs, économie, outils

- [x] **SpellsAhead (bogue).**
  - La relecture de l'entraîneur relançait sa propre relecture (TRAINER_UPDATE après nos filtres) : relecture toutes les 0,25 s tant que l'entraîneur restait ouvert.
  - Les filtres étaient remis avec 0/1 au lieu de vrai/faux (source Blizzard, branche forever : booléens). 0 valant vrai en Lua, un filtre décoché restait coché.
- [x] **Sacs et banque.**
  - Verrou, recharge et argent : seulement ce qui change.
  - Disposition sac fermé regroupée (une fois toutes les 2 s au plus, hors combat) : elle crée les boutons sécurisés des nouvelles cases, qu'un sac ouvert en combat doit déjà avoir.
  - Niveau d'objet mis en cache.
  - Pulsation limitée aux nouveaux objets.
- [x] **Affaires de l'HV.** Recherche avec un budget de temps par image, au lieu de 300 objets par image.
- [x] **Dez, Persos, Réactifs.**
  - Moins de relevés complets des sacs (rafales regroupées ; Persos relève aussi à la déconnexion s'il en reste un).
  - Dez sans objet à désenchanter : événements de sacs coupés hors enchanteur.
- [x] **Chat.**
  - Couleurs des fenêtres posées seulement au changement (opacité, thème).
  - Curseur de défilement sans recoloration à chaque image.
  - Fermetures : aucune n'est plus créée à chaque image dans le pilote actuel.
- [x] **Suivi de quêtes.** UNIT_QUEST_LOG_CHANGED pour le joueur seulement. La mise en page reste regroupée à 0,2 s (pas de comparaison du contenu : gain faible, risque d'oubli).
- [x] **Notes.** Note recomposée seulement si la fenêtre est affichée.
- [x] **Podomètre.**
  - Clés de date gardées jusqu'à minuit.
  - Trophées testés tous les 100 m parcourus au lieu de chaque relevé (deux par seconde).

## Lot 5 — Sauvegarde (temps de connexion et de déconnexion, mémoire)

- [x] **Entraîneurs** (SpellsAheadDB.trainer, 327 Ko). Description retirée quand le sort est connu par son numéro (jamais affichée) : 924 descriptions sur 930, environ 216 Ko en moins dans la sauvegarde actuelle (reste environ 110 Ko). Fait une fois à la connexion (CACHE_VERSION 4).
- [x] **Prix de l'HV.**
  - Historique plafonné aux jours que les calculs utilisent : 14 (valeur marché), ou la durée de la moyenne si elle est plus longue (jusqu'à 30). Une moyenne allongée après coup se remplit au fil des jours.
  - Objets disparus purgés aussi à la connexion.
- [x] **Comptabilité de l'HV (bogue).**
  - Doublons de ventes (acheteur d'abord vide, puis nommé) : ventes et bénéfice gonflés. La clé du courrier ne contient plus l'acheteur (les anciennes clés restent reconnues), et les doublons déjà enregistrés sont fusionnés à la connexion (la première vente garde sa date et prend le nom de l'acheteur).
  - Opérations de plus de 90 jours retirées.
- [x] **Historique du chat, erreurs, noms d'objets, diagnostics.** Déjà plafonnés, rien à ajouter : lignes gardées par fenêtre de chat (réglage, 200 au plus), 200 erreurs, diagnostics des cadres refaits à chaque session.

## Lot 6 — Divers

- [x] **Polices.** Police résolue mise en cache (avant : liste des polices refaite à chaque appel).
- [x] **Minicarte.**
  - Rejets d'épingles mémorisés (réexaminés après 30 s).
  - Zone, coordonnées et heure posées seulement au changement.
  - Pas de doublons dans les textes cachés.
  - Icônes relues une fois par rafale de GROUP_ROSTER_UPDATE (gardé : une icône peut en dépendre).
- [x] **Comm.**
  - Changements de groupe d'une même image regroupés.
  - Accesseur sans fermeture dans la liste de guilde.
  - Mode de noms : déjà lu une fois par appel, laissé tel quel.
- [x] **Erreurs.** En avalanche, la même erreur dans la seconde est seulement comptée, sans relire pile et locales (ni réécrire le journal du jeu).
- [x] **Comparaison.** Rafraîchie seulement si l'envie de comparer change (Ctrl ou Alt seuls ne refont plus rien).
- [x] **`ns.UI.SelectedTab`.** Constante au lieu d'une table neuve.
- [x] **Échelle.** Variables de l'échelle écrites seulement si elles changent.

## Ce qui reste à faire en jeu

Tout le plan est fait et vérifié hors jeu (bancs d'essai : mêmes résultats qu'avant, sauf les changements voulus ci-dessous). **Vu en jeu le 13/10 : tout fonctionne et les performances sont meilleures** ; branche fusionnée dans main. Les points ci-dessous restent à surveiller au fil du jeu.

**Mesurer :** `/reload`, quelques minutes en ville, en combat et en groupe, puis `/corp perf`. Comparer avec main si besoin (`/corp perf reset` remet les compteurs à zéro).

**À regarder en particulier :**
- auras de la cible : elles suivent seules leurs changements (le conteneur du jeu n'est plus rafraîchi à chaque aura) ;
- plaques : couleur « tapé », barres de sort, interruption prête, disposition après un changement de réglage ;
- barres d'action : recharges, couleur utilisable / mana, portée, après un changement de page, de forme ou de familier, et une barre cachée qui réapparaît (combat, véhicule) ;
- fondu des barres « au survol » et « estompées hors combat » ;
- cadres de groupe et de raid : vie, mana, morts, aggro, dissipation, portée, et le déplacement d'un joueur d'un sous-groupe à l'autre ;
- fenêtres habillées à l'ouverture (fiche, grimoire, talents, HV, courrier, marchand, métiers...) ;
- sacs : verrou d'un objet, recharges, or, première ouverture en combat ;
- barre d'infos : or, sacs, durabilité à jour ; liste de guilde ;
- infobulles : bord coloré, bandeau d'infos, prix de l'HV ;
- entraîneur : les filtres de la fenêtre restent comme avant après l'ouverture.

**Changements voulus (pas des régressions) :**
- historique des prix de l'HV : 14 jours gardés (ou la durée de la moyenne si elle est plus longue) au lieu de 30 ;
- erreurs en avalanche : la même erreur dans la seconde est seulement comptée (le journal du jeu ne la réécrit pas) ;
- comptabilité : les ventes en double sont fusionnées à la première connexion (le bénéfice affiché baisse d'autant).
