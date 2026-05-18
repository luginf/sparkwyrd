# Sparkwyrd — Notes pour Claude

## Présentation du projet

**Sparkwyrd** est un outil de génération de texte aléatoire basé sur des tables pondérées, programmé en **Tcl/Tk**. Compatible avec le format `.ipt` d'Inspiration Pad Pro (NBOS).

> Dossier : `sparkwyrd/` (pas `sparkpad`). Ne jamais commiter — l'utilisateur le fait lui-même.

## Structure des fichiers

```
sparkwyrd/
├── Makefile          → construit sparkwyrd.tcl depuis src/
├── sparkwyrd.tcl     → fichier unique généré (make), ne pas éditer
├── demo.ipt          → démo : 560 lignes, 53 tables, toutes les syntaxes
├── README.md
├── manual.md
├── CLAUDE.md         → ce fichier
├── SKILLS.md
└── src/
    ├── header.sh     → polyglot sh/Tcl (3 lignes, shebang + bootstrap)
    ├── engine.tcl    → moteur pur Tcl (parser + générateur, sans Tk)
    ├── cli.tcl       → interface CLI (proc cli_main)
    ├── gui.tcl       → interface Tk (proc gui_main)
    └── main.tcl      → dispatcher --gui / --cli (entry point du build)
```

**Lancement :**
- GUI : `wish src/gui.tcl` ou `./sparkwyrd.tcl --gui`
- CLI : `tclsh src/cli.tcl --cli file.ipt` ou `./sparkwyrd.tcl --cli [opts] file.ipt`
- Build : `make` → génère `sparkwyrd.tcl`

## Ce qui est implémenté (engine.tcl)

### Parser (`parse_ipt`, `parse_ipt_lines`)
- Lecture UTF-8 ligne par ligne
- `Table: NomTable` → dict Tcl
- Items pondérés `N:texte`
- Sentinelles internes : weight=-1 (`Set:` directive), weight=-2 (`Shuffle:`)
- Continuation de ligne `&`
- Commentaires `#`, `;`, `//` (ligne entière et inline)
- En-têtes : `Header:`, `Footer:`, `MaxReps:`, `Formatting:`, `Title:`, `Prompt:`
- Directives de table : `Type:`, `Roll:`, `Default:`, `Shuffle:`, `EndTable:`
- **`Set:` globaux** (avant tout `Table:`) → clé `global_sets` du dict racine
- **`Define: NomVar = expression`** → constante réévaluée à chaque usage, clé `defines` du dict racine
- **`Use: chemin.ipt`** → clé `use_files` du dict racine, traités par `parse_ipt`

### `Define:` — constantes réévaluées
- Format : `Define: NomVar = expression` (avant tout `Table:`)
- Réévaluées à chaque usage (contrairement à `Set:`)
- Peuvent référencer d'autres variables : `Define: Adj = [|grand|petit]`
- Utilisées comme `{$NomVar}` : génère une nouvelle valeur à chaque fois
- Fusion lors des imports : le fichier principal a priorité

### `Use:` — import de fichiers externes (chemins Windows supportés)
- `parse_ipt` collecte la liste `use_files`, puis pour chaque entrée :
  - résout le chemin : d'abord relatif au répertoire du fichier courant, puis CWD
  - parse récursivement (avec protection anti-circulaire via `_loaded`)
  - appelle `ipt_merge` pour fusionner les tables et defines importées
- **Chemins Windows automatiquement convertis** : `nbos\names\human.ipt` → `nbos/Names/Human.ipt` (case-insensitive)
- **Règle de priorité** : le fichier principal a toujours la priorité
- `ipt_empty_parsed` retourne un dict vide (utilisé quand un import circulaire est détecté)
- Warning non-fatal si le fichier `Use:` est introuvable

### Moteur d'expansion (`ipt_expand`, `ipt_roll`)
- Boucle fixpoint : expansion répétée jusqu'à stabilité
- `expand_braces` : `{expr}` avec accolades imbriquées
- `expand_inline_choices` : `[|opt1|opt2|opt3]` avec imbrication
- `expand_bracket_calls` : parse `[@...]`, `[#...]`, `[!...]`, `[texte >> filtre]`
- `expand_conditionals` : `[when]...[do]...[end]` et format legacy Lua
- `[@N table]` avec répétitions ; `[@var=table]` / `[@var==table]` affectation inline
- Paramètres `with` → variables `{$1}`, `{$2}`…
- Filtres chaînés `>> filtre1 >> filtre2`
- **`[!N table]`** : deck pick via `::deck_<tname>` global
- **`[#N table]`** : pick par index (1-based, items réels uniquement, préfixe expansé d'abord)

### Évaluateur d'expressions (`eval_brace_expr`)
- Variables `{$var}` et `{var}`
- Affectation `{var=expr}` (affiche) et `{var==expr}` (silencieux)
- Dés `{NdN}`, `{NdN+M}`, `{NdN-M}`, `{NdN*M}`
- Expressions mathématiques via `expr` (après substitution)
- Fonctions : `max`, `min`, `sqrt`, `abs`, `round`, `floor`, `ceil` → `tcl::mathfunc::*`

### Directives de table
- `Set:` dans le corps → weight=-1, exécuté systématiquement avant pick_weighted
- `Shuffle:` dans le corps → weight=-2, efface le deck `::deck_<nom>` au moment du tirage
- `Set:` globaux (avant `Table:`) → exécutés dans `ipt_generate` avant le premier tirage

### Deck picks `[!N table]`
- Pool : variable globale Tcl `::deck_<tname>` (liste des textes disponibles)
- Pool vide ou absent → reconstruit depuis les items weight > 0
- Tirage : `lreplace $pool $idx $idx` supprime l'item sélectionné
- `ipt_generate` réinitialise tous les decks (`unset -nocomplain ::deck_*`) au début

### Filtres (`apply_filter`)
`lower` `upper` `proper` `bold` `italic` `underline` `trim` `ltrim` `rtrim` `length` `reverse` `left [N]` `right [N]` `substr start [len]` `at sub` `replace /f/r/` `+- / plusminus` `sort` `implode [glue]` `each table` `eachchar table`

### Nettoyage final (`ipt_generate`)
- `\n` → saut de ligne, `\t` → tabulation, `\z` → vide, `\_` → espace
- `\a` → "a" ou "an" (heuristique anglaise)
- Réduction espaces multiples ligne par ligne
- Suppression espace avant ponctuation

### Variables prédéfinies
`{app}` (="Sparkwyrd") `{version}` `{os}` `{date}` `{time}` `{rep}` `{formatting}` `{cli}`

## Ce qui est implémenté (gui.tcl)

- `panedwindow` horizontal : panneau info gauche + zone de sortie droite
- Barre d'outils : Open, Reps (spinbox), Go, Clear, sélecteur Theme
- Liste des tables du fichier chargé
- Barre de statut
- Raccourcis : F5 = Generate, Ctrl+O = Open
- Rendu HTML dans le widget `text` : `<b>` `<i>` `<u>` `<h1>`–`<h3>` `<code>` `<br>` `<p>` `<hr>` + entités
- Thèmes : `light`, `dark`, `sepia` — via `apply_theme` + `option add` + reconfiguration de tous les widgets

## Ce qui est implémenté (cli.tcl)

- Options : `-n <count>`, `-t <table>`, `--html` (garde les balises, défaut = strip), `--sep <str>`, `--list`, `--version`, `--help`
- HTML strippé par défaut ; `--html` pour conserver les balises
- Entités HTML décodées dans les deux modes
- Usage affiche le vrai nom du script via `[file tail [info script]]`
- Entry-point dans `proc cli_main {}` (guard `::sparkwyrd_combined`)

## Architecture du build (Makefile + src/main.tcl)

### Polyglot header (`src/header.sh`)
```sh
#!/bin/sh
# commentaire Tcl — le \ continue la ligne suivante en Tcl \
_w=$(stty -g 2>/dev/null); trap '...' EXIT INT TERM; tclsh "$0" "$@"; exit $?
```
- Shell : lit `#!/bin/sh`, exécute le bootstrap shell, lance `tclsh`, quitte
- Tcl : lit `#` (commentaire), `\` final → la ligne suivante est suite du commentaire → tout ignoré
- `stty` sauvegarde/restaure l'état du terminal → résout le blocage tab-completion

### Dispatcher (`src/main.tcl`)
```
(no args)              → aide une ligne + exit 0   (safe pour la complétion bash)
--gui [file.ipt]       → gui_main
--cli [options] file   → cli_main
-n / -t / --html / … → cli_main (auto-détect par flag CLI)
file.ipt seul          → gui_main (pas de flag CLI reconnu)
```

### Makefile
```
make        → header.sh + engine + cli + gui + main → sparkwyrd.tcl
make clean  → supprime sparkwyrd.tcl
```
- STRIP filtre : `^#!/`, `^source.*engine\.tcl`, `^set script_dir`
- `set ::sparkwyrd_combined 1` injecté en tête → les guards individuels (`if {![info exists ::sparkwyrd_combined]}`) ne s'exécutent pas
- `src/main.tcl` inclus avec `cat` (sans STRIP) en dernier

### Guard dans cli.tcl et gui.tcl
```tcl
proc cli_main {} { ... }
if {![info exists ::sparkwyrd_combined]} { cli_main }
```
Permet l'exécution directe (`tclsh src/cli.tcl`) ET l'inclusion dans le build sans double exécution.

## Ce qui reste à implémenter

- `Type: Lookup` (tables à intervalles `1-5:texte` avec `Roll:` et `Default:`)
- `Type: Dictionary` (clés textuelles, appel via `[#clé table]`)
- `Prompt:` interactif (widgets dans la GUI)
- Variables `{fullpath}`, `{docpath}`, `{self}`
- Arbre de fichiers par catégories (actuellement un seul fichier à la fois)
- Onglet débogage / trace d'expansion

## Pièges découverts (Tcl/Tk)

1. `[+\-]` dans un character class regex → invalide. Utiliser `[-+]`.
2. `[^\S\n]` invalide (`\S` interdit dans bracket expression). Traiter ligne par ligne.
3. `"$var(pattern)"` en double-quoted → Tcl lit comme accès tableau. Utiliser `string map` avec liste.
4. `package require ttk` → erreur sur certains systèmes. Inclus dans `package require Tk` (Tk 8.5+).
5. `expr` avec guillemets échappés dans interpolation → extraire dans une variable d'abord.
6. `proc` imbriquée dans une `proc` → devient globale. Toujours définir au niveau global.
7. `Set:` dans un corps de table = directive, pas item aléatoire. Marquer weight=-1.
8. `ipt_generate` doit passer par `ipt_roll` pour le tirage racine (sinon les directives `Set:` ne s'exécutent pas).
9. `Shuffle:` = weight=-2 (distinct de -1). Ne pas mélanger les sentinelles.
10. `unset $v` sur variable inexistante → erreur. Toujours `unset -nocomplain`.
11. `[#N table]` : filtrer les items weight ≤ 0 avant de calculer l'index.
12. `package require Tk` au niveau global dans le fichier mergé → bloque `tclsh`. Le déplacer dans `gui_main`.
13. Tab-completion bash → exécute le script sans args → lancer `gui_main` bloque sur X display. Fix : sans args, afficher aide + `exit 0`.
14. Shebang `#!/usr/bin/env wish` → bash tente de sourcer le fichier pour la complétion → blocage. Fix : polyglot `#!/bin/sh` + bootstrap shell.
15. `Use:` merge : le fichier principal a priorité. Ne jamais écraser une table existante avec une table importée.
