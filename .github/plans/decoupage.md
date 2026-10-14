# Plan de découpage de CorpUI en plusieurs addons

Plan du 14/10/2026, validé par l'utilisateur le jour même (choix ci-dessous).

## But

- **CorpUI** devient le noyau. Chaque module (ou petit groupe de modules liés) devient un addon **CorpUI_Xxx**.
- Un addon coupé dans la liste des addons du jeu n'est **pas chargé du tout** : moins de mémoire, connexion plus rapide. Aujourd'hui, un module coupé dans la page Modules est quand même chargé.
- **Rien ne change pour le joueur** : mêmes réglages (CorpUIDB gardé tel quel), mêmes commandes `/corp`, même fenêtre d'options.

## Ce que le client permet (vérifié dans la source Blizzard, branche forever)

- **Liste des addons** : `## Group` (posé automatiquement pour les addons au nom et aux dépendances proches) et `## Category`. Les CorpUI_Xxx se rangent donc sous CorpUI, repliables.
- **Ordre de chargement** : `## Dependencies: CorpUI` fait charger le noyau d'abord. Entre deux sous-addons : `## OptionalDeps`.
- **Sauvegardes** : elles appartiennent à l'addon qui les déclare. CorpUIDB et SpellsAheadDB restent déclarées par le noyau : aucune migration, rien de perdu.
- **Partage du code** : chaque addon a son propre espace de noms. Le noyau publie le sien dans une globale `CorpUI`, à nous (aucune globale de Blizzard touchée), et chaque fichier des sous-addons commence par `local ns = CorpUI`.

## Ce qu'il faut démêler d'abord

Des fonctions d'usage général vivent aujourd'hui dans des modules, et d'autres modules s'en servent :

| Aujourd'hui dans | Fonctions | Utilisées par |
|---|---|---|
| Buffs | couleur et icône de classe, temps, sorts connus | Cadres, Groupe, Plaques, Infobulles, Infos, Persos, Métiers, Rappels, noyau |
| Dissipation | sons (liste, lecture) | Chasseur, Podomètre |
| Barres | raccourcis (`ShortKey`, `RegisterBindable`, mode raccourcis rapides) | Menus, Dez, Raid |
| Comm | échanges entre joueurs CorpUI | Buffs, Dissipation, Notes, Recharges, Podomètre |
| Habillage | registre des fenêtres habillées | SpellsAhead, Talents |

Elles passent dans le noyau. Les autres appels d'un module à un autre (par exemple les prix de l'HV dans les métiers, ou la barre d'infos sous le chat) deviennent facultatifs : l'appel ne se fait que si l'autre addon est là. Le relevé complet est fait (script `deps_modules.js`, une trentaine de liens).

## Découpage proposé : 32 addons

Un addon par module. On ne regroupe que les modules qui ne marchent pas l'un sans l'autre.

| Addon | Contenu actuel | Remarque |
|---|---|---|
| **CorpUI** (noyau) | Locales, textes, Core, Movers, polices, défauts, images et sons, Profils, Modules, Installation, Erreurs, Comm | Erreurs reste au noyau : il doit charger en premier pour attraper les erreurs des autres |
| CorpUI_Cadres | Cadres (centre, coups, ressources, totems, éditeur), Auras, Incantations, Groupe | un seul éditeur, liens dans les deux sens |
| CorpUI_Chasseur | Chasseur | |
| CorpUI_Barres | Barres, Appel des totems, Menus | Menus et Barres s'appellent l'un l'autre |
| CorpUI_Experience | Expérience | |
| CorpUI_Minicarte | Minicarte, points de vol | |
| CorpUI_Infos | Barre d'infos | |
| CorpUI_Quetes | Suivi de quêtes | |
| CorpUI_Plaques | Plaques de nom | |
| CorpUI_Infobulles | Infobulles | |
| CorpUI_Chat | Discussion | |
| CorpUI_Compteur | Compteur, Dégâts, Menace | liens dans les deux sens |
| CorpUI_Sacs | Sacs, banque | |
| CorpUI_Butin | Butin, fil du butin | même dossier |
| CorpUI_Eclats | Éclats du butin | |
| CorpUI_Marchand | Marchand, Réactifs | liens dans les deux sens |
| CorpUI_Habillage | les 22 fichiers de l'habillage | |
| CorpUI_Buffs | Buffs | |
| CorpUI_Dissipation | Dissipation | |
| CorpUI_Rappels | Rappels | |
| CorpUI_Recharges | Recharges | |
| CorpUI_Notes | Notes | |
| CorpUI_Raid | Barre de raid | |
| CorpUI_Invitations | Invitations | |
| CorpUI_Clics | Sorts au clic | |
| CorpUI_Persos | Persos | |
| CorpUI_Metiers | Métiers | prix de l'HV si CorpUI_HV est là |
| CorpUI_HV | Hôtel des ventes (19 fichiers), Dez | Dez a besoin des valeurs de désenchantement de l'HV |
| CorpUI_Talents | Talents | |
| CorpUI_Sorts | Sorts à venir (SpellsAhead) | |
| CorpUI_Jeux | Murloc, Minerais, Podomètre | le podomètre se sert du registre des jeux |

Variante plus compacte possible : **un addon par page d'options**, soit une vingtaine.

## Dépôt et installation

- **Release** : un seul zip qui contient tous les dossiers (CorpUI, CorpUI_Cadres…). Le script de release met la version dans tous les .toc, et le workflow vérifie qu'elles sont identiques.
- **Mise à jour d'une ancienne installation** : supprimer l'ancien dossier CorpUI, puis décompresser. Les réglages restent dans `WTF`.
- **Côté développement**, deux possibilités :
  - **A (recommandée)** : le dépôt sort de `AddOns` (par exemple `_classic_beta_\CorpUI-dev`), avec tous les dossiers d'addons côte à côte. Un script crée les liens (jonctions Windows, sans droits d'administrateur) dans `AddOns`. C'est la forme la plus propre, et la plus proche du zip.
  - **B** : le dépôt reste dans `AddOns\CorpUI`, avec les sous-addons en sous-dossiers, et des jonctions `AddOns\CorpUI_Xxx` vers ces sous-dossiers. Moins de changement, mais le dossier du noyau contient les autres.

## Page Modules

- Proposition : la page Modules (et la grille de l'assistant d'installation) pilote directement les addons. Cocher ou décocher active ou désactive l'addon CorpUI_Xxx (C_AddOns.EnableAddOn / DisableAddOn), puis demande un rechargement.
- Les modules qui partagent un addon (par exemple Compteur et Menace) gardent l'interrupteur actuel.
- La fenêtre d'options ne montre que ce qui est chargé (déjà le cas : elle part des modules inscrits).

## Étapes (branche `decoupage`, un commit par étape, bancs d'essai à chaque fois)

1. **Outils** : les bancs d'essai suivent les fichiers déplacés (table d'adresses générée depuis les .toc), sans réécrire les 190 bancs. Ajout d'un banc **« chaque addon seul avec le noyau »** : chargement, connexion, quelques images, aucune erreur. Ajout d'un banc **« tous sauf un »**.
2. **Noyau** : globale `CorpUI`, puis les fonctions partagées passent au noyau (Comm, raccourcis, sons, classes, registre de l'habillage). CorpUI reste un seul addon : les bancs doivent rester identiques.
3. **Appels facultatifs** : chaque lien d'un module à un autre est protégé, et le banc « seul avec le noyau » passe pour chaque futur addon.
4. **Découpage** : déplacement des dossiers (avec `git mv` : l'historique suit), un .toc par addon (titre, notes en 10 langues, dépendances, groupe, version), en-têtes des 159 fichiers, script de liens. Tous les bancs sont verts.
5. **Page Modules** et assistant reliés aux addons.
6. **Release** : workflow à plusieurs dossiers, README (installation), notes.
7. **En jeu** : liste des addons (regroupement), couper quelques addons, fenêtre d'options, `/corp perf`. Puis fusion dans main et release.

## Ce qui reste comme avant

- Aucune globale de Blizzard touchée, aucun crochet : la globale `CorpUI` est à nous.
- Images, polices et sons : dans le noyau, chemins inchangés. Exception possible : les images des jeux (16 Mo) partent avec CorpUI_Jeux.
- Doom reste un addon à part, sans changement.

## Choix de l'utilisateur (14/10)

1. **Granularité** : 32 addons, un par module (regroupés seulement quand ils ne marchent pas l'un sans l'autre).
2. **Dépôt** : A. Le dépôt vit dans `_classic_beta_\CorpUI-dev`, tous les addons côte à côte, avec des liens (jonctions) dans `AddOns`. Le travail se fait dans ce nouveau dossier, sur la branche `decoupage` : l'addon installé dans `AddOns\CorpUI` (main) ne change pas tant que la bascule n'est pas faite.
3. **Page Modules** : elle active ou désactive les addons eux-mêmes, puis demande un rechargement.
4. **Version** : 1.8.0.
