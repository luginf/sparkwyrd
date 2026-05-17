# Sparkwyrd — Notes pour Claude

## Présentation du projet

**Sparkwyrd** est un outil de génération de texte aléatoire basé sur des tables pondérées, programmé en **Tcl/Tk**. Il est compatible avec le format de fichier `.ipt` d'Inspiration Pad Pro (NBOS). C'est un programme autonome avec interface graphique Tk.

> Le nom du dossier est `sparkwyrd` (pas `sparkpad`).

## Fichiers du projet

| Fichier | Rôle |
|---|---|
| `engine.tcl` | Moteur pur Tcl — parser + générateur, sans dépendance Tk |
| `sparkpad.tcl` | Interface graphique Tk — sources `engine.tcl` |
| `cli.tcl` | Interface ligne de commande (en cours d'écriture) |
| `demo.ipt` | Fichier de démonstration : 560 lignes, 53 tables, couvre toutes les syntaxes (fantasy/steampunk/pirate) |
| `CLAUDE.md` | Ce fichier |
| `SKILLS.md` | Référence technique Tcl/Tk pour ce projet |

Les fichiers de référence (prototype Lua, exemple `.ipt`, spec) se trouvent dans le dossier parent `sparkpad/` s'ils ont été conservés.

## Ce qui est implémenté (engine.tcl)

### Parser (`parse_ipt`, `parse_ipt_lines`)
- Lecture UTF-8 ligne par ligne
- `Table: NomTable` → dict Tcl
- Items pondérés `N:texte` (weight=-1 pour directives `Set:` dans une table, weight=-2 pour `Shuffle:`)
- Continuation de ligne `&`
- Commentaires `#`, `;`, `//` (ligne entière et inline)
- En-têtes : `Header:`, `Footer:`, `MaxReps:`, `Formatting:`, `Title:`, `Use:`, `Prompt:`
- Directives de table : `Type:`, `Roll:`, `Default:`, `Shuffle:`, `EndTable:`
- **`Set:` globaux** (avant tout `Table:`) : parsés dans une clé `global_sets` du dict racine

### Moteur d'expansion (`ipt_expand`, `ipt_roll`)
- Boucle fixpoint : expansion répétée jusqu'à stabilité
- **`expand_braces`** : expansion de `{expr}` avec accolades imbriquées
- **`expand_inline_choices`** : `[|opt1|opt2|opt3]` avec imbrication
- **`expand_bracket_calls`** : parse `[@...]`, `[#...]`, `[!...]`, `[texte >> filtre]`
- **`expand_conditionals`** : `[when]...[do]...[end]` et format legacy Lua `[if {$x}==val]...[else]...]`
- Appels `[@N table]` avec répétitions
- Paramètres `with` → variables `{$1}`, `{$2}`...
- Affectation inline `[@var=table]` et silencieuse `[@var==table]`
- Filtres chaînés `>> filtre1 >> filtre2`
- **`[!N table]`** : tirage sans remise (deck pick) via `::deck_<tname>`
- **`[#N table]`** : tirage par index (1-based, items réels uniquement) ; le préfixe numérique est d'abord expansé via `ipt_expand`

### Évaluateur d'expressions (`eval_brace_expr`)
- Variables `{$var}` et `{var}`
- Affectation `{var=expr}` (affiche) et `{var==expr}` (silencieux)
- Dés `{NdN}`, `{NdN+M}`, `{NdN-M}`
- Expressions mathématiques via `expr` (après substitution des dés et vars)
- Fonctions : `max`, `min`, `sqrt`, `abs`, `round`, `floor`, `ceil` → mappées vers `tcl::mathfunc::*`

### Directives `Set:` dans les tables
- Les lignes `Set:var=val` dans le corps d'une table sont marquées `weight=-1`
- `ipt_roll` les exécute **systématiquement** avant le tirage (comportement SparkPad réel, pas Lua)
- La valeur peut contenir des sous-tables `[@...]`

### `Set:` globaux (avant toute table)
- Parsés dans la clé `global_sets` du dict racine (liste de paires `{varname value}`)
- Exécutés par `ipt_generate` avant le premier tirage de table, dans les variables partagées
- Permettent de définir des variables mondiales (ex. `Set: world = [@world_name]`) disponibles partout

### Deck picks `[!N table]`
- Pool stocké dans la variable globale Tcl `::deck_<tname>` (liste des items du pool courant)
- Si le pool est vide ou inexistant, il est reconstruit à partir des items réels (weight > 0) de la table
- Chaque tirage supprime l'item sélectionné du pool (tirage sans remise)
- `ipt_generate` réinitialise tous les decks (`unset -nocomplain ::deck_*`) au début de chaque appel

### Directive `Shuffle:` dans une table
- Stockée comme item `weight=-2` dans la liste d'items de la table
- Quand `ipt_roll` traite la table et rencontre un tel item à la position tirée, il fait `unset -nocomplain ::deck_<tablename>` — le deck est vidé et sera reconstruit au prochain tirage `[!]`

### Filtres (`apply_filter`)
`lower`, `upper`, `proper`, `bold`, `italic`, `underline`, `trim`, `ltrim`, `rtrim`, `length`, `reverse`, `left [N]`, `right [N]`, `substr start [len]`, `at substring`, `replace /find/repl/`, `+- / plusminus`, `sort`, `implode [glue]`, `each table`, `eachchar table`

### Nettoyage final (`ipt_generate`)
- `\n` → vrai saut de ligne, `\t` → tabulation, `\z` → vide, `\_` → espace
- `\a` → "a" ou "an" selon voyelle suivante (heuristique anglaise)
- Réduction des espaces multiples ligne par ligne (sans toucher les `\n`)
- Suppression des espaces avant ponctuation `, . : ; ! ?`

### Variables prédéfinies
`{app}` (= "Sparkwyrd") `{version}` `{os}` `{date}` `{time}` `{rep}` `{formatting}` `{cli}`

## Ce qui est implémenté (sparkpad.tcl)

### Interface graphique
- `panedwindow` horizontal : panneau info gauche + zone de sortie droite
- Barre d'outils : Ouvrir, Répétitions (spinbox), Go, Effacer, sélecteur de Thème
- Liste des tables du fichier chargé (widget `text` en lecture seule)
- Affichage Header:/Footer: dans le panneau gauche
- Barre de statut en bas
- Raccourcis : F5 = Générer, Ctrl+O = Ouvrir

### Système de thèmes
Voir section dédiée ci-dessous.

### Rendu HTML (`html_insert`, `html_current_tag`)
Parseur de balises HTML inline dans le widget `text` de Tk :
- `<b>`, `<strong>` → tag `tbold`
- `<i>`, `<em>` → tag `titalic`
- `<u>` → tag `tunderline`
- `<b><i>` combinés → tag `tbold_italic`
- `<h1>`, `<h2>`, `<h3>` → tags `th1`, `th2`, `th3`
- `<code>`, `<tt>` → tag `tcode` (police fixe, fond coloré)
- `<br>`, `<br/>` → saut de ligne
- `<p>`, `</p>` → saut de ligne
- `<hr>` → ligne de séparation
- Entités : `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&nbsp;`

## Système de thèmes

### Architecture
```
array ::themes(nom) = dict de couleurs
proc T {key}        → lit la couleur courante
proc apply_theme {}  → reconfigure tous les widgets + tags
```

`apply_theme` est appelé au démarrage ET à chaque changement via le menu.
Elle reconfigure : `option add` (widgets futurs) + tous les widgets existants + tous les tags du widget `text`.

### Thèmes disponibles
| Nom | Description |
|---|---|
| `clair` | Fond blanc, texte noir, vert pour Go |
| `sombre` | Fond #1e1e1e style éditeur, titres dorés |
| `sepia` | Fond parchemin brun, ambiance jeu de rôle |

### Clés de palette (par thème)
`bg` `bg2` `bg_tb` `fg` `fg2` `fg_link` `sep` `out_bg` `out_fg` `out_title` `out_sep` `out_h1` `out_h2` `out_h3` `out_code_bg` `btn_bg` `btn_fg` `btn_go_bg` `btn_go_fg` `sel_bg` `sel_fg`

Pour ajouter un thème : ajouter une entrée dans `array set ::themes` et une ligne dans le menu `.tb.theme_mb.m`.

## Ce qui reste à implémenter

- `Type: Lookup` (tables à intervalles `1-5:texte` avec `Roll:` et `Default:`)
- `Type: Dictionary` (clés textuelles, appel via `[#clé table]`)
- `Use: fichier.ipt` (chargement de fichiers externes)
- `Prompt:` interactif (widgets dans l'UI)
- `Define:` (constante réévaluée à chaque usage)
- Variables `{fullpath}`, `{docpath}`, `{self}`
- Arbre de fichiers par catégories (actuellement : un seul fichier à la fois)
- Onglet débogage / trace d'expansion
- `cli.tcl` : interface ligne de commande (en cours)

## Pièges découverts (Tcl/Tk)

1. `[+\-]` dans un character class regex Tcl → invalide. Utiliser `[-+]` (tiret en premier).
2. `[^\S\n]` invalide (shorthand `\S` interdit dans bracket expression Tcl). Traiter ligne par ligne avec `split`/`join`.
3. `"(pattern)$var(pattern)"` en double-quoted → Tcl interprète `$var(...)` comme accès tableau. Utiliser `string map` avec liste ou `${var}`.
4. `package require ttk` → erreur. En Tk 8.5+, `ttk` est inclus dans `package require Tk`. Ne pas le requérir séparément.
5. `expr {$n>1?"s":""}` avec guillemets échappés → invalide dans certains contextes. Extraire dans une variable : `set s [expr {$n>1?"s":""}]`.
6. Proc imbriquée dans une proc (`proc` dans `proc`) → la proc interne devient globale et se redéfinit à chaque appel. Toujours définir au niveau global.
7. `Set:` dans le corps d'une table = directive (SparkPad réel), pas item aléatoire (comportement Lua). Marquer weight=-1 et exécuter avant pick_weighted.
8. `ipt_generate` doit déléguer à `ipt_roll` pour le tirage racine (pas appeler `pick_weighted` directement), sinon les directives `Set:` ne s'exécutent pas.
9. `Shuffle:` dans une table = weight=-2 (distinct de -1 pour `Set:`). Ne pas les mélanger dans la même valeur sentinelle.
10. `unset -nocomplain` est indispensable pour vider un deck : `unset ::deck_foo` plante si la variable n'existe pas.
11. Les `[#N table]` s'appuient sur les items réels uniquement (weight > 0) — les items weight=-1 (`Set:`) et weight=-2 (`Shuffle:`) ne comptent pas dans l'index 1-based.
