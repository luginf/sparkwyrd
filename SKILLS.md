# Sparkwyrd — Référence technique Tcl/Tk

Techniques Tcl/Tk utilisées ou utiles pour ce projet.

---

## Tcl — Fondamentaux

### Chaînes et manipulation de texte

```tcl
string trim $s
string tolower / toupper $s
string length $s
string range $s 0 4          ;# sous-chaîne [0..4] inclus
string index $s 3
string first "sub" $text     ;# position, -1 si absent
string map [list "a" "b" "c" "d"] $s   ;# remplacements multiples
string map {"\\n" "\n" "\\t" "\t"} $s  ;# séquences d'échappement
```

### Regex

```tcl
regexp {^(\d+):(.+)$} $line -> weight content
regsub -all { {2,}} $line " " line   ;# réduire espaces multiples

# Pièges :
# [-+] et non [+\-]  — \- dans un character class est invalide en Tcl ARE
# \S, \W etc. sont invalides DANS un bracket expression [...]
# Toujours utiliser des accolades pour les patterns : {pattern}
```

### Dict (tables nommées, données structurées)

```tcl
dict set d key value
dict get d key
dict exists d key
set d [dict create k1 v1 k2 v2]
foreach {k v} $d { ... }
```

### Array (contexte mutable partagé par upvar)

```tcl
array set vars {}
set vars(nom) "valeur"
set v $vars(nom)
info exists vars(nom)    ;# tester existence
array names vars         ;# liste des clés
array size vars
```

**Règle** : `array` ne peut pas être passé par valeur. Toujours passer le *nom* et utiliser `upvar` :

```tcl
proc ma_proc {vars_var} {
    upvar $vars_var vars
    set vars(x) "hello"   ;# modifie l'original
}
array set mon_array {}
ma_proc mon_array
```

`upvar` fonctionne correctement en chaîne profonde (proc → proc → proc) tant que chaque niveau passe le nom de la variable locale.

### Aléatoire

```tcl
expr {srand([clock milliseconds])}      ;# initialiser une fois au démarrage
expr {int(rand() * $N)}                 ;# entier [0, N-1]
```

### Évaluation d'expressions

```tcl
# Toujours avec accolades pour éviter la double évaluation
expr {$a + $b * 2}
expr {round(1.7)}
expr {max(3, 7, 2)}      ;# via tcl::mathfunc::*

# Pour une expression dynamique construite en string (après substitution des vars/dés) :
if {[catch {set result [expr $safe_expr]} err]} {
    # expr échoue si l'expression est invalide
}
```

### Listes

```tcl
lappend mylist item
lindex $mylist 0
llength $mylist
lrange $mylist 1 end
lsort $mylist
lreverse $mylist               ;# inverser
join $list ", "                ;# joindre
split "a,b,c" ","              ;# découper
```

### Parsing ligne par ligne

```tcl
set fd [open $filename r]
fconfigure $fd -encoding utf-8   ;# indispensable pour le français
while {[gets $fd line] >= 0} {
    set line [string trim $line]
}
close $fd
```

---

## Tcl — Patterns spécifiques au projet

### Tokeniser un texte avec balises imbriquées

Trouver l'accolade/crochet fermant en comptant la profondeur :

```tcl
set depth 1
set j [expr {$i + 1}]
while {$j < $len && $depth > 0} {
    set ch [string index $s $j]
    if {$ch eq "\["} { incr depth }
    if {$ch eq "\]"} { incr depth -1 }
    incr j
}
# $j pointe juste après le ] fermant
set inner [string range $s [expr {$i+1}] [expr {$j-2}]]
```

### Substitution de chaîne sans regex (plus sûr pour les variables utilisateur)

```tcl
# Remplacer une séquence littérale par une valeur :
set s [string map [list "\\n" "\n" "\\t" "\t"] $s]

# Pour des variables issues du fichier .ipt :
# NE PAS utiliser regsub avec $var dans le pattern (risque d'injection regex)
# Utiliser string map avec list :
set s [string map [list "{${varname}}" $value] $s]
```

### Proc imbriquée — piège à éviter

```tcl
# FAUX : inner_proc devient globale et se redéfinit à chaque appel de outer
proc outer {} {
    proc inner {} { ... }   # ← NE PAS FAIRE
}

# CORRECT : définir toutes les procs au niveau global
proc inner {} { ... }
proc outer {} { inner ... }
```

---

## Tk — Interface graphique

### Principes de base

```tcl
package require Tk     ;# charge aussi ttk en Tk 8.5+
# NE PAS faire : package require ttk  (erreur sur certains systèmes)

wm title . "Sparkwyrd"
wm geometry . "920x620"
wm minsize . 640 400
```

### Layouts : pack vs grid

```tcl
# pack — pour des arrangements linéaires (toolbar, status bar)
pack .btn -side left -padx 6 -pady 4

# grid — pour des grilles (panneau gauche avec labels + widgets)
grid .lbl -row 0 -column 0 -sticky ew -padx 8
grid columnconfigure . 0 -weight 1
grid rowconfigure    . 5 -weight 1   ;# ligne extensible
```

### PanedWindow (séparateur redimensionnable)

```tcl
panedwindow .pw -orient horizontal -sashwidth 5 -sashrelief flat
pack .pw -fill both -expand 1
frame .left -width 210
frame .right
pack propagate .left 0      ;# empêcher le rétrécissement auto
.pw add .left  -minsize 180
.pw add .right -minsize 300
```

### Widget text (zone de sortie riche)

```tcl
text .out -wrap word -state disabled -font {Georgia 12} \
    -padx 16 -pady 12

# Toujours passer en normal avant d'écrire, disabled après
.out configure -state normal
.out delete 1.0 end
.out insert end "texte\n" mon_tag
.out configure -state disabled
.out see 1.0   ;# remonter en haut
```

### Tags du widget text

```tcl
# Définir les tags (une fois à la création ou dans apply_theme)
.out tag configure tbold      -font {Georgia 12 bold}
.out tag configure titalic    -font {Georgia 12 italic}
.out tag configure tunderline -font {Georgia 12} -underline 1
.out tag configure th1        -font {Georgia 16 bold} -foreground "#1a1a2e"
.out tag configure tcode      -font {TkFixedFont 11} -background "#f0f0f0"

# Insérer avec tag :
.out insert end "gras\n" tbold
# Insérer sans tag (hérite du fg/bg du widget) :
.out insert end "normal\n"
```

**Important** : les tags `tbold`, `titalic` etc. doivent avoir un `-foreground` explicite, sinon ils héritent du foreground *système* (blanc sur bureau sombre → invisible).

### Système de thèmes (pattern utilisé dans sparkpad.tcl)

```tcl
# 1. Déclarer des palettes
array set ::themes {}
set ::themes(clair) {bg #ffffff fg #111111 btn_bg #dcdcdc ...}
set ::themes(sombre) {bg #1e1e1e fg #d4d4d4 btn_bg #3c3c3c ...}

# 2. Accesseur
proc T {key} { return [dict get $::themes($::current_theme) $key] }

# 3. Appliquer le thème (reconfigure tout)
proc apply_theme {{theme ""}} {
    if {$theme ne ""} { set ::current_theme $theme }

    # Base de données d'options Tk (widgets futurs)
    option add *Background [T bg]  interactive
    option add *Foreground [T fg]  interactive

    # Widgets existants (reconfigurer explicitement)
    .tb configure -bg [T bg_tb]
    .right.out configure -bg [T out_bg] -fg [T out_fg]

    # Tags du widget text
    .right.out tag configure tbody -foreground [T out_fg]
    .right.out tag configure tbold -font {Georgia 12 bold} -foreground [T out_fg]
    # ...
}

# 4. Sélecteur dans l'UI
menubutton .tb.theme_mb -textvariable ::current_theme -menu .tb.theme_mb.m
menu .tb.theme_mb.m -tearoff 0
foreach th {clair sombre sepia} {
    .tb.theme_mb.m add command -label $th -command [list apply_theme $th]
}
```

**Règle** : `option add` influence les *nouveaux* widgets. Pour les widgets déjà créés, il faut `configure` explicitement.

### MenuButton (menu déroulant dans toolbar)

```tcl
menubutton .mb -textvariable ::ma_var -relief raised -menu .mb.m
menu .mb.m -tearoff 0
.mb.m add command -label "Option 1" -command { ... }
.mb.m add separator
.mb.m add command -label "Option 2" -command { ... }
```

### Spinbox (saisie numérique)

```tcl
spinbox .reps -from 1 -to 999 -width 4 \
    -textvariable ::reps_count \
    -validate key -validatecommand {string is integer %P}
```

### Parseur HTML inline → tags widget text

Pattern utilisé dans `html_insert` :

```tcl
# Tokeniser : alterner texte et <balises>
set pos 0
while {$pos < [string length $html]} {
    set lt [string first "<" $html $pos]
    if {$lt < 0} { # texte final ; break }
    if {$lt > $pos} { # texte avant la balise }
    set gt [string first ">" $html $lt]
    # inner = contenu entre < et >
    set tag_name [string tolower [lindex [split [string trim $inner]] 0]]
    switch -- $tag_name {
        b       { set active(b) 1 }
        /b      { set active(b) 0 }
        br - {br/} { $w insert end "\n" $base }
        # ...
    }
}
```

### Deck pick `[!N table]` — pattern d'implémentation

Le tirage sans remise repose sur une variable globale Tcl `::deck_<tname>` qui sert de pool mutable.

```tcl
# Réinitialiser tous les decks au début de chaque génération
proc ipt_generate {ipt tname args} {
    # vider tous les pools existants
    foreach v [info vars ::deck_*] { unset $v }
    # ... suite de ipt_generate
}

# Tirer un item sans remise
proc deck_pick {ipt tname} {
    set vname "::deck_${tname}"
    # Construire le pool si absent ou vide
    if {![info exists $vname] || [llength [set $vname]] == 0} {
        set pool {}
        foreach item [dict get $ipt tables $tname items] {
            set w [dict get $item weight]
            if {$w > 0} {
                # répéter l'item selon son poids
                for {set i 0} {$i < $w} {incr i} {
                    lappend pool [dict get $item text]
                }
            }
        }
        set $vname $pool
    }
    # Tirer un index aléatoire, retirer l'item du pool
    set idx [expr {int(rand() * [llength [set $vname]])}]
    set result [lindex [set $vname] $idx]
    set $vname [lreplace [set $vname] $idx $idx]
    return $result
}
```

**Points clés :**
- `info vars ::deck_*` liste toutes les variables de deck existantes.
- `lreplace $list $idx $idx` supprime l'élément à l'index `$idx` (en passant le même index deux fois).
- `unset -nocomplain $vname` est préférable à `unset $vname` pour éviter une erreur si la variable n'existe pas.
- La directive `Shuffle:` (weight=-2 dans la table) déclenche `unset -nocomplain ::deck_<tname>` — le pool sera reconstruit au prochain tirage `[!]`.

### `global_sets` — Set: avant toute table

Les directives `Set:` placées avant le premier `Table:` sont stockées dans la clé `global_sets` du dict racine (liste de dicts `{varname name value val}`). `ipt_generate` les exécute avant tout tirage :

```tcl
# Dans le parser : détecter Set: avant toute table
if {![dict exists $ipt tables] && [regexp {^Set:\s*(\w+)\s*=\s*(.*)$} $line -> vn vv]} {
    dict lappend ipt global_sets [dict create varname $vn value $vv]
}

# Dans ipt_generate : exécuter les global_sets
if {[dict exists $ipt global_sets]} {
    foreach gs [dict get $ipt global_sets] {
        set vname [dict get $gs varname]
        set raw   [dict get $gs value]
        set vars($vname) [ipt_expand $ipt $raw vars]
    }
}
```

### `[#N table]` — tirage par index

Quand le tag est `#` et que le corps commence par un entier, `pick_index` est positionné (à la place de `reps`). L'exécution récupère le Nième item réel (1-based) :

```tcl
# Dans expand_bracket_calls :
if {$tag eq "#"} {
    if {[regexp {^(\d+)\s+(.+)$} $body -> idx tname]} {
        set pick_index $idx   ;# 1-based
    } elseif {[regexp {^\{[^}]+\}\s+(.+)$} $body -> tname]} {
        # le préfixe peut être une variable : [{n} table]
        # expanser d'abord via ipt_expand, puis extraire l'entier
        set expanded [ipt_expand $ipt $body vars_ref]
        regexp {^(\d+)\s+(.+)$} $expanded -> pick_index tname
    }
}

# Dans ipt_roll / le bloc d'exécution :
if {[info exists pick_index]} {
    set real_items [lsearch -all -inline -not -index {weight} -exact -1 \
                        [dict get $ipt tables $tname items]]
    # filtrer aussi weight=-2 (Shuffle:)
    set real_items [lmap it $real_items {
        expr {[dict get $it weight] > 0 ? $it : [continue]}
    }]
    set result [dict get [lindex $real_items [expr {$pick_index - 1}]] text]
}
```

**Note :** le préfixe numérique dans `[#{var} table]` est expansé via `ipt_expand` *avant* d'extraire l'entier, ce qui permet d'écrire `[#{roll} Treasure]` où `{roll}` est une variable contenant un nombre.

---

## Pièges identifiés (résumé)

| Piège | Solution |
|---|---|
| `[+\-]` dans regex | Utiliser `[-+]` (tiret en premier dans la classe) |
| `[^\S\n]` dans regex | Invalide en Tcl. Traiter ligne par ligne |
| `"$var(pattern)"` en double-quoted | Tcl croit que c'est un array. Utiliser `string map` avec list |
| `package require ttk` | Erreur. Tk 8.5+ l'inclut, ne pas le requérir |
| `expr {$n>1?"s":""}` dans une interpolation | Extraire dans une variable avant |
| `proc` définie dans une `proc` | Devient globale, se redéfinit. Définir au niveau global |
| Widgets sans `-fg` sur bureau sombre | Toujours spécifier `-fg` et `-foreground` explicitement |
| Tags widget text sans `-foreground` | Héritent du système → invisible sur fond sombre |
| `pick_weighted` appelé directement sur la table racine | Passer par `ipt_roll` pour exécuter les directives `Set:` |
| `unset $v` sur variable inexistante | Erreur fatale. Toujours utiliser `unset -nocomplain $v` |
| `lreplace $list $idx $idx` | Supprime un seul élément à l'index `$idx` (donner le même index deux fois) |
| `weight=-1` et `weight=-2` mélangés | Garder les sentinelles distinctes : -1 = `Set:`, -2 = `Shuffle:` |
| `[#{var} table]` — préfixe non expansé | Toujours expanser le corps via `ipt_expand` avant d'en extraire l'index entier |
| `info vars ::deck_*` en début de `ipt_generate` | Permet de vider tous les pools en une passe sans connaître les noms de tables |
