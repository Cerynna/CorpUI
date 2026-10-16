# Plan : montée des métiers (fonctions de skillup-forever)

Demande du 16/10/2026 : intégrer à CorpUI les fonctions de [skillup-forever](https://github.com/cjber/skillup-forever).
Cet addon est sous GPL-3.0 : on réécrit ses fonctions dans le module Métiers, sans reprendre son code ni ses fichiers de données.

## Données

Elles viennent des tables du jeu Forever (DB2), publiées sur wago.tools (produit `wowf`, 1.60.1). C'est la même source que skillup-forever, mais notre script génère notre propre fichier (`.github/scripts/metiers_donnees.js` → `CorpUI_Metiers/Metiers/Donnees.lua`). Ce fichier contient :
- `SkillLineAbility` : le métier de chaque recette, et ses seuils (orange = compétence requise, jaune, gris ; vert = milieu entre jaune et gris) ;
- `SpellReagents` : les composants et leur nombre ;
- `SpellEffect` : l'objet fabriqué et sa quantité ;
- `ItemSparse` : le prix d'achat chez les marchands.

Les noms viennent du jeu, dans ta langue.

## Fonctions

| | Fonction | Où |
| --- | --- | --- |
| A | Sur chaque recette : chance de montée (%) et coût par point de compétence. Dans l'infobulle : barre des seuils orange, jaune, vert, gris avec ta compétence marquée, et prix des composants. Tri par chance ou par coût. | fenêtre des métiers (nos textes posés sur ses lignes, sans crochet) |
| B | Route de montée : de ta compétence à une cible, quelles recettes fabriquer et combien (en comptant les montées ratées), quand passer à l'entraîneur, coût total. Elle remplit la liste de courses existante. | onglet « Montée » du volet CorpUI des métiers |
| C | Chez l'entraîneur : chance et coût sur chaque recette, et une flèche sur la plus utile. | fenêtre de l'entraîneur |
| D | Infobulle d'un composant : quantité nécessaire à la route suivie. | infobulles |
| E | Nœuds de récolte : icône en rouge si ta compétence d'herboristerie ou de minage est trop basse. | icônes de récolte sur la minicarte |
| F | Équipement fabricable : le meilleur objet que tu peux fabriquer pour chaque emplacement. | onglet facultatif |

**Chance de montée (formule de Classic)** : orange 100 % ; entre jaune et gris, (gris − compétence) ÷ (gris − jaune) ; gris 0 %.

**Prix** : le prix de vente chez les marchands pour ce qui s'y achète, sinon la valeur du marché du module Hôtel des ventes. Ce que tu récoltes toi-même compte comme gratuit (option).

## Avancement

**Choix de l'utilisateur (16/10)** : toutes les fonctions (A à F), en quatre livraisons :
1. les données, puis A ;
2. B ;
3. C et D ;
4. E et F.

**Livraison 1 (à tester en jeu)** :
- `Metiers/Donnees.lua` est généré par `.github/scripts/metiers_donnees.js` à partir des tables `wowf` 1.60.1.70245 : 2 524 recettes et 2 381 objets.
  - Seuls les métiers de Classic et les poisons sont gardés.
  - Dans ces tables, le seuil « requis » vaut 1 pour presque toutes les recettes. Le vrai seuil d'apprentissage vient de l'entraîneur (livraison 3).
- `Metiers/Montee.lua` fournit :
  - les seuils, la chance et la couleur de chaque recette ;
  - les prix : relevés chez les marchands, fournitures connues, ce qu'on récolte soi-même (option), sinon l'hôtel des ventes ;
  - le coût par fabrication et par point ;
  - la chance et le coût posés sur les lignes de Blizzard ;
  - l'onglet « Montée » : la recette choisie avec la barre des seuils, puis la liste triée par coût ou par chance.
- Branchements : 3ᵉ onglet du volet (`File.lua`), réglages ajoutés par `M.optionHooks` (`Courses.lua`).
- Banc `t_montee` : 36 vérifications.
