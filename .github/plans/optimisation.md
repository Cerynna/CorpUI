# Plan d'optimisation de CorpUI

Branche `optimisation` (13/10/2026). Le plan s'appuie sur quatre audits du code (socle, combat, sacs et économie, habillage) : plus de 100 constats avec leurs numéros de ligne.

Chaque point coché est fait, testé hors jeu (bancs d'essai : tous les bancs donnent les mêmes résultats qu'avant) et commité. Aucun n'a encore été testé en jeu.

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

- [ ] **`ns.ModuleOff`** arrête aussi les pilotes du module coupé.
- [ ] **Habillage.**
  - Les 20 pilotes ne tournent plus fenêtres fermées.
  - PNJ n'est plus vérifié à chaque image fenêtres fermées.
  - Skins et Communs ne repeignent que les éléments des fenêtres ouvertes.
  - Le journal de quêtes ne refait plus sa passe de textes carte fermée.
- [ ] **Hôtel des ventes, courrier, butin, métiers, SpellsAhead, talents, chat, chevrons, parent caché, icône d'erreurs, poignées, file de Comm.** Pilotes posés seulement pendant qu'ils servent.

## Lot 4 — Sacs, économie, outils

- [ ] **SpellsAhead (bogue).**
  - La relecture de l'entraîneur relançait sa propre relecture (TRAINER_UPDATE après nos filtres).
  - Les filtres étaient remis avec 0/1 au lieu de vrai/faux.
- [ ] **Sacs et banque.**
  - Verrou, recharge et argent : seulement ce qui change.
  - Disposition différée sac fermé.
  - Niveau d'objet mis en cache.
  - Pulsation limitée aux nouveaux objets.
- [ ] **Affaires de l'HV.** Recherche avec un budget de temps par image, au lieu de 300 objets par image.
- [ ] **Dez, Persos, Réactifs.**
  - Moins de relevés complets des sacs.
  - Dez sans objet à désenchanter : événements de sacs coupés hors enchanteur.
- [ ] **Chat.**
  - Plus de fermeture créée à chaque image.
  - Couleurs posées seulement au changement.
  - Curseur de défilement sans recoloration à chaque image.
- [ ] **Suivi de quêtes.** UNIT_QUEST_LOG_CHANGED pour le joueur seulement, et mise en page sautée si rien n'a changé.
- [ ] **Notes.** Note recomposée seulement si la fenêtre est affichée.
- [ ] **Podomètre.**
  - Clés de date gardées jusqu'à minuit.
  - Trophées testés seulement au franchissement d'un seuil.

## Lot 5 — Sauvegarde (temps de connexion et de déconnexion, mémoire)

- [ ] **Entraîneurs** (SpellsAheadDB.trainer, 329 Ko). Description retirée quand le sort est connu par son numéro (jamais affichée) ; cible environ 100 Ko.
- [ ] **Prix de l'HV.**
  - Historique plafonné à 14 jours (ce que les calculs utilisent) au lieu de 30.
  - Objets disparus purgés aussi à la connexion.
- [ ] **Comptabilité de l'HV (bogue).**
  - Doublons de ventes (acheteur d'abord vide, puis nommé) : ventes et bénéfice gonflés.
  - Opérations de plus de 90 jours retirées.
- [ ] **Historique du chat, erreurs, noms d'objets, diagnostics.** Purge des anciens.

## Lot 6 — Divers

- [ ] **Polices.** Police résolue mise en cache.
- [ ] **Minicarte.**
  - Rejets d'épingles mémorisés.
  - Zone et heure seulement au changement.
  - Pas de doublons dans les textes cachés.
  - GROUP_ROSTER_UPDATE retiré des icônes.
- [ ] **Comm.**
  - Changements de groupe regroupés.
  - Mode de noms mis en cache.
  - Accesseur sans fermeture dans la liste de guilde.
- [ ] **Erreurs.** En avalanche, une erreur déjà vue est seulement comptée.
- [ ] **Comparaison.** Rafraîchie seulement si l'envie de comparer change.
- [ ] **`ns.UI.SelectedTab`.** Constante au lieu d'une table neuve.
- [ ] **Échelle.** Variables de l'échelle écrites seulement si elles changent.

## Ce qui reste à faire en jeu

Pour chaque lot : `/reload`, `/corp perf` après quelques minutes de jeu (en ville, en combat, en groupe), et vérifier que rien n'a changé à l'écran.

Points à regarder en particulier :
- le conteneur d'auras de la cible suit bien seul ses changements ;
- la couleur « tapé » des plaques ;
- le fondu des barres ;
- les fenêtres habillées à l'ouverture.
