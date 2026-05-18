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

### Notebook (tabbed interface)

```tcl
package require Tk

# Créer un notebook (ttk::notebook, pas tk::notebook)
ttk::notebook .nb
pack .nb -fill both -expand 1

# Ajouter des frames comme onglets
frame .nb.tab1
frame .nb.tab2
.nb add .nb.tab1 -text "Tab 1"
.nb add .nb.tab2 -text "Tab 2"

# Remplir les onglets avec des widgets
text .nb.tab1.txt -wrap word
pack .nb.tab1.txt -fill both -expand 1

# Sélectionner un onglet par programme
.nb select .nb.tab2
# ou via index : .nb select 0
```

**Points clés :**
- `ttk::notebook` (pas `tk::notebook`) offre une meilleure apparence cross-platform
- `.nb add frame -text "label"` pour ajouter un onglet
- `.nb select frame` ou `.nb select index` pour changer d'onglet
- Les frames ajoutées au notebook peuvent contenir n'importe quel widget

### Listbox (widget sélectionnable avec binding)

```tcl
# Créer une listbox avec scrollbar
frame .list_frame
listbox .list_frame.lb -selectmode single -highlightthickness 1 \
    -activestyle underline -width 30 -height 15
scrollbar .list_frame.sb -command [list .list_frame.lb yview]
.list_frame.lb configure -yscrollcommand [list .list_frame.sb set]

pack .list_frame.lb -side left -fill both -expand 1
pack .list_frame.sb -side right -fill y

# Remplir la listbox
foreach item {Item1 Item2 Item3} {
    .list_frame.lb insert end $item
}

# Binding : quand on clique sur une ligne
bind .list_frame.lb <ButtonRelease-1> {
    set idx [.list_frame.lb index @%x,%y]
    if {$idx >= 0} {
        set line [.list_frame.lb get $idx]
        puts "Clicked on index $idx: $line"
    }
}

# Binding : quand la sélection change (plus robuste que ButtonRelease)
.list_frame.lb bind <<ListboxSelect>> {
    set selection [.list_frame.lb curselection]
    if {[llength $selection] > 0} {
        set line [.list_frame.lb get [lindex $selection 0]]
        puts "Selected: $line"
    }
}

# Récupérer la ligne actuelle
set current_idx [.list_frame.lb index active]   ;# index de sélection
set current_text [.list_frame.lb get $current_idx]

# Thème : colorer la sélection
.list_frame.lb configure -selectbackground #0078d4 -selectforeground white
```

**Points clés :**
- `-activestyle underline` souligne la ligne active (meilleur que la couleur par défaut)
- `-highlightthickness 1` ajoute un border au widget
- `<ButtonRelease-1>` capture le clic gauche, puis `index @%x,%y` donne l'index de la ligne
- `<<ListboxSelect>>` est plus robuste pour les changements de sélection au clavier
- `curselection` retourne une liste des indices sélectionnés

### Dialog toplevel (fenêtre modale ou flottante)

```tcl
proc open_dialog {} {
    set w .my_dialog
    
    # Éviter les doublons : si la fenêtre existe déjà, la raiser
    if {[winfo exists $w]} {
        raise $w
        focus .find_entry
        return
    }
    
    # Créer la fenêtre toplevel
    toplevel $w
    wm title $w "Titre du dialog"
    wm geometry $w "400x200"
    wm transient $w .       ;# lier au parent (important pour le Z-order)
    wm resizable $w 0 0     ;# interdire le redimensionnement
    
    # Contenu : frame principal
    frame $w.content -padx 10 -pady 10
    pack $w.content -fill both -expand 1
    
    # Label + entry
    label $w.content.lbl -text "Entrez du texte:"
    entry $w.content.entry
    pack $w.content.lbl -anchor w
    pack $w.content.entry -fill x -pady 5
    
    # Boutons
    frame $w.buttons
    button $w.buttons.ok -text "OK" -command [list on_dialog_ok $w]
    button $w.buttons.cancel -text "Annuler" -command "destroy $w"
    pack $w.buttons.ok $w.buttons.cancel -side left -padx 2
    pack $w.buttons -fill x
    
    # Donner le focus à l'entry
    focus $w.content.entry
    
    # Bind Escape pour fermer
    bind $w <Escape> "destroy $w"
    
    # Bind Return pour valider
    bind $w.content.entry <Return> [list on_dialog_ok $w]
}

proc on_dialog_ok {w} {
    set text [.my_dialog.content.entry get]
    puts "User entered: $text"
    destroy $w
}
```

**Points clés :**
- `wm transient $w .` lie la fenêtre au parent (elle disparaît si le parent se ferme)
- Vérifier `[winfo exists $w]` pour éviter les doublons
- `focus $w.widget` donne le focus à un widget spécifique
- Bind `<Escape>` et `<Return>` pour une meilleure UX

### Text widget — recherche et coloration syntaxique

```tcl
# Créer un text widget
text .edit -wrap word -font {Georgia 12} -width 60 -height 20
scrollbar .edit.sb -command [list .edit yview]
.edit configure -yscrollcommand [list .edit.sb set]

# Définir des tags pour la coloration
.edit tag configure keyword -foreground #0000ff -font {Georgia 12 bold}
.edit tag configure comment -foreground #808080 -font {Georgia 12 italic}
.edit tag configure string -foreground #ff0000

# Chercher une chaîne (case-insensitive)
proc search_text {w search_term} {
    set current_pos [.edit index insert]
    
    # Chercher à partir de la position actuelle
    set found [.edit search -nocase -count len -- $search_term $current_pos end]
    
    # Si pas trouvé, recommencer du début
    if {$found eq ""} {
        set found [.edit search -nocase -count len -- $search_term 1.0 end]
    }
    
    if {$found ne ""} {
        # Ôter la surbrillance précédente
        .edit tag remove highlight 1.0 end
        # Ajouter la nouvelle surbrillance
        .edit tag add highlight $found "$found+$len c"
        # Configurer le style du tag
        .edit tag configure highlight -background yellow
        # Naviguer vers la position
        .edit mark set insert $found
        .edit see $found
    }
}

# Coloration syntaxique ligne par ligne
proc highlight_editor {w} {
    # Ôter tous les tags
    $w tag remove keyword 1.0 end
    $w tag remove comment 1.0 end
    
    # Parcourir les lignes
    set line_num 1
    while {[$w get $line_num.0 $line_num.end] ne ""} {
        set text [$w get $line_num.0 $line_num.end]
        set text_stripped [string trim $text]
        
        # Déterminer le type de ligne et appliquer le tag
        if {[regexp {^#} $text_stripped]} {
            # Commentaire
            $w tag add comment "$line_num.0" "$line_num.end"
        } elseif {[regexp {^(Table|Use|Set|Define):} $text_stripped]} {
            # Directive
            $w tag add keyword "$line_num.0" "$line_num.end"
        }
        
        incr line_num
    }
}

# Applier la coloration au chargement
highlight_editor .edit
```

**Points clés :**
- `$w search -nocase` pour chercher case-insensitive
- `$w tag add nom début fin` pour appliquer un tag
- `$w tag remove nom début fin` pour ôter un tag
- Parcourir ligne par ligne : `[$w get $line_num.0 $line_num.end]` (indices Tcl text)
- Ne pas chercher sur le texte entier sur les gros fichiers (lent)
- `$w see position` pour scroller vers la position

### File I/O UTF-8 et préservation de position

```tcl
# Charger un fichier dans un text widget
proc load_file_to_editor {w filename} {
    # Lire le fichier en UTF-8
    if {[catch {
        set fd [open $filename r]
        fconfigure $fd -encoding utf-8
        set content [read $fd]
        close $fd
    } err]} {
        puts stderr "Error reading file: $err"
        return
    }
    
    # Insérer dans le widget
    $w configure -state normal
    $w delete 1.0 end
    $w insert end $content
    $w configure -state normal
    $w mark set insert 1.0
}

# Sauvegarder avec préservation de position
proc save_file_from_editor {w filename} {
    # Mémoriser la position du curseur
    set saved_pos [$w index insert]
    
    # Lire le contenu du widget (sans le dernier newline)
    set content [$w get 1.0 end-1c]
    
    # Écrire en UTF-8
    if {[catch {
        set fd [open $filename w]
        fconfigure $fd -encoding utf-8
        puts -nonewline $fd $content
        close $fd
    } err]} {
        puts stderr "Error writing file: $err"
        return
    }
    
    # Recharger le fichier pour synchroniser la GUI
    load_file_to_editor $w $filename
    
    # Restaurer la position (avec un délai pour la reconfiguration du widget)
    after 100 [list restore_cursor_position $w $saved_pos]
}

proc restore_cursor_position {w pos} {
    catch {
        $w mark set insert $pos
        $w see $pos
    }
}
```

**Points clés :**
- Toujours utiliser `fconfigure $fd -encoding utf-8` pour les fichiers UTF-8
- `puts -nonewline` pour écrire sans newline final (ou avec `[string trimright]`)
- `$w get 1.0 end-1c` pour lire tout sauf le dernier newline implicite du widget
- Mémoriser la position **avant** de modifier le widget
- Restaurer dans un `after 100` pour laisser le widget se reconfigurer

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

### Polyglot sh/Tcl — shebang sans blocage de complétion

Le problème : `#!/usr/bin/env wish` amène bash à exécuter le script pendant la complétion → tentative d'ouvrir un display X → blocage.

La solution : un header polyglot qui est à la fois un script shell valide et un commentaire Tcl valide.

```sh
#!/bin/sh
# Sparkwyrd — sh/Tcl polyglot bootstrap
# Le backslash en fin de ligne continue le commentaire Tcl à la ligne suivante \
_w=$(stty -g 2>/dev/null); trap '[ -n "$_w" ] && stty "$_w" 2>/dev/null' EXIT INT TERM; tclsh "$0" "$@"; exit $?
```

**Comment ça marche :**

| Interpréteur | Lecture |
|---|---|
| Shell (`/bin/sh`) | Ligne 1 = shebang. Lignes 2-3 = commentaires shell. Ligne 4 = commandes : sauvegarde stty, trap restauration, relance avec `tclsh`, quitte. |
| Tcl | Ligne 1 = `#` (commentaire). Ligne 2-3 = commentaire avec `\` final → continuation → lignes 2+3+4 forment **un seul** commentaire Tcl. |

Le `stty -g` / `trap` préserve l'état du terminal (important pour la complétion bash/zsh).

**Règle absolue** : ne jamais ajouter un quatrième niveau d'indirection. Le `\` en fin de ligne 3 doit être le **dernier caractère** de cette ligne (pas d'espace après).

### Dispatcher GUI/CLI dans un fichier unique

Quand engine + cli + gui sont mergés, les deux entry-points coexistent. Solution : guard + dispatcher.

```tcl
# Dans chaque fichier source (cli.tcl, gui.tcl) :
proc cli_main {} { ... }  ;# ou gui_main
if {![info exists ::sparkwyrd_combined]} { cli_main }

# Dans le Makefile, injecté en tête du fichier mergé :
set ::sparkwyrd_combined 1

# Dans src/main.tcl (inclus en dernier) :
proc sparkwyrd_dispatch {} {
    global argv
    set cli_flags {-n -t --html --sep --list --version --help}
    set mode ""; set rest {}
    foreach arg $argv {
        switch -- $arg {
            --gui { set mode gui }
            --cli { set mode cli }
            default { lappend rest $arg }
        }
    }
    set argv $rest
    # Sans aucun argument → aide + exit 0 (safe pour bash completion)
    if {$mode eq "" && [llength $rest] == 0} {
        puts "Usage: [file tail [info script]] --gui [file] | --cli [opts] file"
        exit 0
    }
    # Auto-détect
    if {$mode eq ""} {
        set mode gui
        foreach a $rest {
            if {$a in $cli_flags || [string match "-*" $a]} { set mode cli; break }
        }
    }
    if {$mode eq "gui"} {
        if {[catch {gui_main} err]} {
            puts stderr "Cannot start GUI: $err\nUse --cli for command-line mode."
            exit 1
        }
    } else { cli_main }
}
sparkwyrd_dispatch
```

**Points clés :**
- `::sparkwyrd_combined` distingue exécution directe d'un source vs inclusion dans le build.
- `package require Tk` doit être dans `gui_main {}`, jamais au niveau global — sinon il s'exécute même avec `tclsh`.
- Le détecteur `[info commands wm]` n'est pas fiable : sur certains systèmes, `package require Tk` réussit même avec `tclsh` si le display est disponible.

### `Use:` — import avec support des chemins Windows

```tcl
# parse_ipt avec protection circulaire
proc parse_ipt {filename {_loaded {}}} {
    set norm [file normalize $filename]
    if {$norm in $_loaded} { return [ipt_empty_parsed] }  ;# import circulaire
    lappend _loaded $norm

    # ... lire et parser le fichier ...
    set parsed [parse_ipt_lines $lines]

    # Résoudre et fusionner chaque Use:
    foreach rel [dict get $parsed use_files] {
        set found [normalize_use_path $rel [file dirname $norm]]
        if {![file exists $found]} { 
            puts stderr "Warning: Use: file not found: $rel"; 
            continue 
        }

        if {[catch {set used [parse_ipt $found $_loaded]} err]} { continue }
        set parsed [ipt_merge $parsed $used]   ;# main a priorité
    }
    return $parsed
}

# Normalise les chemins Windows et cherche case-insensitive
proc normalize_use_path {rel basedir} {
    # Remplacer backslashes par slashes
    set path [string map {\\ /} $rel]

    # Chercher avec le chemin exact
    set candidates [list \
        [file join $basedir $path] \
        [file normalize $path]]

    foreach c $candidates {
        if {[file exists $c]} { return $c }
    }

    # Pour les chemins "nbos/..." chercher dans Common/ (case-insensitive)
    if {[regexp -nocase {^(nbos|srd|common)/(.*)$} $path -> subdir rest]} {
        set searchdir $basedir
        for {set i 0} {$i < 5} {incr i} {
            set parent [file normalize [file join $searchdir ".."]]
            if {$parent eq $searchdir} { break }
            set searchdir $parent

            # Chercher avec case-insensitive
            set found [find_case_insensitive \
                [file join $searchdir "Common"] "$subdir/$rest"]
            if {$found ne ""} { return $found }
        }
    }

    return [file join $basedir $path]
}

# Cherche un fichier en ignorant la casse de tous les composants
proc find_case_insensitive {basedir path} {
    set components [split $path "/"]
    set current $basedir

    foreach comp $components {
        if {![file isdirectory $current]} { return "" }
        set found ""
        foreach f [glob -directory $current -nocomplain * .*] {
            if {[string tolower [file tail $f]] eq [string tolower $comp]} {
                set found $f
                break
            }
        }
        if {$found eq ""} { return "" }
        set current $found
    }

    if {[file exists $current]} { return $current }
    return ""
}

# ipt_merge : used ne peut qu'AJOUTER des tables (jamais écraser)
proc ipt_merge {main used} {
    set m_tables [dict get $main tables]
    foreach tname [dict get $used order] {
        if {[dict exists $m_tables $tname]} continue   ;# main gagne
        dict set m_tables $tname [dict get [dict get $used tables] $tname]
        # Copier aussi types/rolls/defaults si présents dans used
        foreach key {types rolls defaults} {
            if {[dict exists [dict get $used $key] $tname]} {
                dict set [dict get $main $key] $tname \
                    [dict get [dict get $used $key] $tname]
            }
        }
    }
    dict set main tables $m_tables
    return $main
}

# Retourné quand un import circulaire est détecté
proc ipt_empty_parsed {} {
    return [dict create header {Header {} Footer {} MaxReps 0 Formatting html Title {}} \
        tables {} order {} types {} rolls {} defaults {} prompts {} global_sets {} use_files {}]
}
```

**Points clés :**
- `file normalize` est indispensable pour la détection circulaire : `./foo.ipt` et `foo.ipt` donneraient sinon deux clés différentes.
- La recherche est d'abord relative au fichier courant (pas au CWD), puis CWD. Cela permet les bibliothèques co-localisées.
- Un warning non-fatal est émis si le fichier est introuvable (pas d'`exit`).
- Le merge `types`/`rolls`/`defaults` est nécessaire pour que les Lookup et Dictionary tables importées fonctionnent correctement.

### `Define:` — constantes réévaluées à chaque usage

Les directives `Define:` placées avant le premier `Table:` sont stockées dans la clé `defines` du dict racine (liste de `{varname expression}`). Contrairement à `Set:`, elles sont réévaluées à chaque usage via `lookup_define` :

```tcl
# Dans le parser : détecter Define: avant toute table
if {[regexp -nocase {^Define:\s*(\w+)\s*=\s*(.*)$} $line -> var val]} {
    lappend defines [list $var [string trim $val]]
}

# Dans eval_brace_expr : chercher dans les defines si variable non définie
if {[regexp {^\$(.+)$} $e -> var]} {
    if {[info exists vars($var)]} {
        return $vars($var)
    }
    # Chercher dans les defines
    if {[info exists vars(__defines)]} {
        set val [lookup_define $var $vars(__defines) vars]
        if {$val ne ""} { return $val }
    }
    return "\[UNDEF:$var\]"
}

# Dans ipt_generate : passer les defines dans l'array vars
set vars(__defines) $defines
```

**Points clés :**
- Les defines sont évalués à chaque appel (contrairement à `Set:` qui ne s'exécutent qu'une fois)
- Peuvent contenir des expressions : `Define: Color = [|rouge|bleu|vert]`
- Fusion lors des imports : le fichier principal a priorité (comme pour les tables)

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
| `package require Tk` au niveau global dans le build | Bloque `tclsh` même en mode CLI. Déplacer dans `gui_main {}` |
| Shebang `#!/usr/bin/env wish` | bash tente de l'exécuter pendant la complétion → blocage X. Utiliser le polyglot `#!/bin/sh` |
| Script sans args → `gui_main` par défaut | bash complétion exécute le script sans args → blocage X. Fix : sans args, aide + `exit 0` |
| `Use:` merge — ordre de priorité | Le fichier principal prime. N'ajouter une table importée que si son nom est absent du principal |
| Import circulaire via `Use:` | Passer une liste `_loaded` de chemins normalisés en paramètre de `parse_ipt`; retourner `ipt_empty_parsed` si déjà chargé |
| Chemins Windows dans `Use:` | `nbos\names\Human.ipt` → convertir `\` en `/` et chercher case-insensitive. Fonction `normalize_use_path` |
| `Define:` réévaluation | Chaque usage de `{$NomVar}` évalue la Define à nouveau. Stocker dans `vars(__defines)` et appeler `lookup_define` |
