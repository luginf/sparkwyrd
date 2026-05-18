# Éditeur de fichiers .ipt intégré à Sparkwyrd

# ============================================================
# VARIABLES
# ============================================================

set ::editor_file ""

# ============================================================
# ÉDITEUR — INITIALISATION
# ============================================================

proc editor_init {nb} {
    frame $nb.edit
    $nb add $nb.edit -text "Éditer"

    # Text widget éditable avec scrollbar
    text $nb.edit.ed -wrap word -font {Georgia 12} \
        -padx 8 -pady 8 -width 60 -height 30
    scrollbar $nb.edit.sb -command [list $nb.edit.ed yview]
    $nb.edit.ed configure -yscrollcommand [list $nb.edit.sb set]

    pack $nb.edit.ed -side left -fill both -expand 1
    pack $nb.edit.sb -side right -fill y

    # Bind Ctrl+S pour sauvegarder
    bind $nb.edit.ed <Control-s> { editor_save }

    # Tags de coloration
    $nb.edit.ed tag configure ed_table -foreground "#0047AB" -font {Georgia 12 bold}
    $nb.edit.ed tag configure ed_directive -foreground "#8B4513"
    $nb.edit.ed tag configure ed_comment -foreground "#808080"
    $nb.edit.ed tag configure ed_weight -foreground "#228B22"
}

# ============================================================
# ÉDITEUR — CHARGER FICHIER
# ============================================================

proc editor_load {path} {
    set ::editor_file $path

    # Lire le fichier en UTF-8
    if {[catch {
        set fd [open $path r]
        fconfigure $fd -encoding utf-8
        set content [read $fd]
        close $fd
    } err]} {
        puts stderr "Error loading file: $err"
        return
    }

    # Insérer dans l'éditeur
    set ed .right.nb.edit.ed
    $ed configure -state normal
    $ed delete 1.0 end
    $ed insert end $content
    $ed configure -state normal
    $ed mark set insert 1.0

    # Appliquer la coloration
    highlight_editor
}

# ============================================================
# ÉDITEUR — SAUVEGARDER
# ============================================================

proc editor_save {} {
    set ed .right.nb.edit.ed
    set content [$ed get 1.0 end-1c]

    if {$::editor_file eq ""} {
        puts stderr "No file loaded to save"
        return
    }

    # Écrire le fichier en UTF-8
    if {[catch {
        set fd [open $::editor_file w]
        fconfigure $fd -encoding utf-8
        puts -nonewline $fd $content
        close $fd
    } err]} {
        puts stderr "Error saving file: $err"
        return
    }

    # Recharger le fichier dans la GUI
    cmd_load_file $::editor_file
}

# ============================================================
# ÉDITEUR — ALLER À UNE TABLE
# ============================================================

proc editor_goto_table {name} {
    set ed .right.nb.edit.ed

    # Search line by line for "Table: name" (case-insensitive)
    set line_num 1
    while {[$ed get $line_num.0 $line_num.end] ne ""} {
        set text [$ed get $line_num.0 $line_num.end]
        set text_stripped [string trim $text]

        # Check if this line matches "Table: name"
        if {[string tolower $text_stripped] eq "table: [string tolower $name]"} {
            set pos $line_num.0
            $ed mark set insert $pos
            $ed see $pos
            $ed tag remove sel 1.0 end
            set end "$pos lineend"
            $ed tag add sel "$pos linestart" $end
            .right.nb select .right.nb.edit
            return
        }
        incr line_num
    }
}

# ============================================================
# ÉDITEUR — COLORATION SYNTAXIQUE
# ============================================================

proc highlight_editor {} {
    set ed .right.nb.edit.ed

    # Effacer tous les tags existants
    $ed tag remove ed_table 1.0 end
    $ed tag remove ed_directive 1.0 end
    $ed tag remove ed_comment 1.0 end
    $ed tag remove ed_weight 1.0 end

    # Parcourir les lignes
    set line_num 1
    while {[$ed get $line_num.0 $line_num.end] ne ""} {
        set text [$ed get $line_num.0 $line_num.end]
        set text_stripped [string trim $text]

        # Table: NomTable
        if {[regexp {^Table:\s*(\w+)} $text_stripped -> tname]} {
            set idx [$ed search -nocase "Table:" "$line_num.0" "$line_num.end"]
            if {$idx ne ""} {
                $ed tag add ed_table "$idx" "$idx lineend"
            }
        }

        # Directives (Use:, Set:, Define:, Header:, etc.)
        if {[regexp {^(Use|Set|Define|Header|Footer|Type|Roll|Default|Shuffle|Prompt|MaxReps|Formatting|Title|Deck):\s*} $text_stripped]} {
            set regex {^(Use|Set|Define|Header|Footer|Type|Roll|Default|Shuffle|Prompt|MaxReps|Formatting|Title|Deck):}
            set idx [$ed search -regexp $regex "$line_num.0" "$line_num.end"]
            if {$idx ne ""} {
                set end [$ed search -regexp {:} $idx "$line_num.end"]
                if {$end ne ""} {
                    set end [$ed index "$end+1c"]
                    $ed tag add ed_directive $idx $end
                }
            }
        }

        # Commentaires (#, ;, //)
        if {[regexp {^\s*(#|;|//)} $text_stripped]} {
            $ed tag add ed_comment "$line_num.0" "$line_num.end"
        }

        # Poids (N:) au début d'une ligne
        if {[regexp {^\d+:\s*} $text_stripped]} {
            regexp -indices {\d+} $text_stripped match
            if {[info exists match]} {
                set start [lindex $match 0]
                set end [lindex $match 1]
                $ed tag add ed_weight "$line_num.$start" "$line_num.[expr {$end+1}]"
            }
        }

        incr line_num
    }
}

# ============================================================
# ÉDITEUR — THÈME
# ============================================================

proc editor_apply_theme {} {
    set ed .right.nb.edit.ed

    if {[catch {
        # Recharger les couleurs depuis les thèmes
        set bg [T bg]
        set fg [T fg]

        $ed configure -bg $bg -fg $fg

        # Recolorer les tags
        $ed tag configure ed_table -foreground [T ed_table_fg]
        $ed tag configure ed_directive -foreground [T ed_directive_fg]
        $ed tag configure ed_comment -foreground [T ed_comment_fg]
        $ed tag configure ed_weight -foreground [T ed_weight_fg]
    }]} {
        # Si les clés de thème n'existent pas, utiliser des défauts
        $ed configure -bg [T bg] -fg [T fg]
        $ed tag configure ed_table -foreground "#0047AB" -font {Georgia 12 bold}
        $ed tag configure ed_directive -foreground "#8B4513"
        $ed tag configure ed_comment -foreground "#808080"
        $ed tag configure ed_weight -foreground "#228B22"
    }
}

# ============================================================
# GUARD BUILD
# ============================================================

if {![info exists ::sparkwyrd_combined]} {
    # Code de test / développement
}
