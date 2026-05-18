#!/bin/sh
# Sparkwyrd — sh/Tcl polyglot bootstrap
# The backslash at the end of this line is a Tcl line-continuation inside a comment \
_w=$(stty -g 2>/dev/null); trap '[ -n "$_w" ] && stty "$_w" 2>/dev/null' EXIT INT TERM; tclsh "$0" "$@"; exit $?

set script_dir [file normalize [file dirname [info script]]]
set ::sparkwyrd_combined 1

# === engine ===
# Sparkpad — moteur de génération (sans dépendance Tk)

# ============================================================
# ALÉATOIRE
# ============================================================
expr {srand([clock milliseconds])}

proc rand_int {n} {
    if {$n <= 0} { return 0 }
    return [expr {int(rand() * $n)}]
}

# ============================================================
# PATH NORMALIZATION
# ============================================================
# Normalise les chemins Windows/Unix et cherche les fichiers en case-insensitive
proc normalize_use_path {rel basedir} {
    # Remplacer les backslashes par des slashes
    set path [string map {\\ /} $rel]

    # Chercher d'abord avec le chemin exact depuis basedir
    set candidates [list \
        [file join $basedir $path] \
        [file normalize $path]]

    foreach c $candidates {
        if {[file exists $c]} { return $c }
    }

    # Pour les chemins commençant par "nbos/" "srd/" "common/":
    # Chercher dans tous les répertoires parents pour trouver Common
    if {[regexp -nocase {^(nbos|srd|common)/(.*)$} $path -> subdir rest]} {
        set searchdir $basedir
        # Remonter jusqu'à 5 niveaux
        for {set i 0} {$i < 5} {incr i} {
            set parent [file normalize [file join $searchdir ".."]]
            if {$parent eq $searchdir} { break }
            set searchdir $parent

            # Chercher Common/subdir/rest avec tous les chemins components en case-insensitive
            set commondir [file join $searchdir "Common"]
            if {[file isdirectory $commondir]} {
                set found [find_case_insensitive $commondir "$subdir/$rest"]
                if {$found ne ""} { return $found }
            }
        }
    }

    # Retourner le chemin normalisé même s'il n'existe pas (pour le message d'erreur)
    return [file join $basedir $path]
}

# Helper: trouve un fichier en ignorant la casse des composants du chemin
proc find_case_insensitive {basedir path} {
    set components [split $path "/"]
    set current $basedir

    foreach comp $components {
        if {![file isdirectory $current]} { return "" }

        # Chercher un fichier/répertoire correspondant (case-insensitive)
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

# ============================================================
# PARSER
# ============================================================
# Retourne un dict avec :
#   header   : dict (Header, Footer, MaxReps, Formatting, Title)
#   tables   : dict  nom -> liste d'items {weight N text T}
#   order    : liste des noms de tables dans l'ordre de déclaration
#   types    : dict  nom -> Weighted|Lookup|Dictionary
#   rolls    : dict  nom -> expression de dé (Lookup)
#   defaults : dict  nom -> valeur par défaut
#   prompts  : liste de spécs Prompt

proc parse_ipt {filename {_loaded {}}} {
    set norm [file normalize $filename]

    # Circular import guard
    if {$norm in $_loaded} { return [ipt_empty_parsed] }
    lappend _loaded $norm

    set fd [open $filename r]
    fconfigure $fd -encoding utf-8
    set lines {}
    while {[gets $fd line] >= 0} { lappend lines $line }
    close $fd

    set parsed  [parse_ipt_lines $lines]
    set basedir [file dirname $norm]

    # Resolve and merge Use: files — used tables are added only if not
    # already defined in the main file (main file always takes priority).
    foreach rel [dict get $parsed use_files] {
        set found [normalize_use_path $rel $basedir]
        if {![file exists $found]} {
            puts stderr "Warning: Use: file not found: $rel"
            continue
        }
        if {[catch {set used [parse_ipt $found $_loaded]} err]} {
            puts stderr "Warning: cannot load Use: $found — $err"
            continue
        }
        set parsed [ipt_merge $parsed $used]
    }

    return $parsed
}

# Returns a minimal empty parsed structure (used for circular import guard)
proc ipt_empty_parsed {} {
    return [dict create \
        header      {Header {} Footer {} MaxReps 0 Formatting html Title {}} \
        tables      {}  order   {}  types   {}  rolls {} \
        defaults    {}  prompts {}  global_sets {}  use_files {}  defines {}]
}

# Merges `used` into `main`: tables/types/rolls/defaults from `used`
# are added only when the name does not already exist in `main`.
proc ipt_merge {main used} {
    set m_tables   [dict get $main tables]
    set m_types    [dict get $main types]
    set m_rolls    [dict get $main rolls]
    set m_defaults [dict get $main defaults]
    set m_defines  [expr {[dict exists $main defines] ? [dict get $main defines] : {}}]

    set u_tables   [dict get $used tables]
    set u_types    [dict get $used types]
    set u_rolls    [dict get $used rolls]
    set u_defaults [dict get $used defaults]
    set u_defines  [expr {[dict exists $used defines] ? [dict get $used defines] : {}}]

    foreach tname [dict get $used order] {
        if {[dict exists $m_tables $tname]} continue
        dict set m_tables $tname [dict get $u_tables $tname]
        if {[dict exists $u_types    $tname]} { dict set m_types    $tname [dict get $u_types    $tname] }
        if {[dict exists $u_rolls    $tname]} { dict set m_rolls    $tname [dict get $u_rolls    $tname] }
        if {[dict exists $u_defaults $tname]} { dict set m_defaults $tname [dict get $u_defaults $tname] }
    }

    # Merger les defines du fichier inclus (main a priorité)
    foreach def $u_defines {
        set dname [lindex $def 0]
        set already_exists 0
        foreach mdef $m_defines {
            if {[lindex $mdef 0] eq $dname} {
                set already_exists 1
                break
            }
        }
        if {!$already_exists} {
            lappend m_defines $def
        }
    }

    dict set main tables   $m_tables
    dict set main types    $m_types
    dict set main rolls    $m_rolls
    dict set main defaults $m_defaults
    dict set main defines  $m_defines
    return $main
}

proc parse_ipt_lines {lines} {
    set tables      {}
    set order       {}
    set types       {}
    set rolls       {}
    set defaults    {}
    set header      {Header {} Footer {} MaxReps 0 Formatting html Title {}}
    set prompts     {}
    set global_sets {}    ;# liste de {varname expression} globaux
    set use_files   {}    ;# liste de chemins Use:
    set defines     {}    ;# liste de {varname expression} pour Define:

    set current_name  ""
    set current_items {}
    set buffer        ""

    foreach raw $lines {
        set line [string trim $raw]

        # Commentaires ligne entière
        if {$line eq ""} {
            if {$buffer ne "" && $current_name ne ""} {
                set current_items [ipt_flush_buffer $buffer $current_items]
                set buffer ""
            }
            continue
        }
        if {[string match "#*"  $line] ||
            [string match ";*"  $line] ||
            [string match "//*" $line]} { continue }

        # Commentaire inline //
        set ci [string first "//" $line]
        if {$ci > 0} { set line [string trim [string range $line 0 [expr {$ci-1}]]] }
        if {$line eq ""} { continue }

        # ---- Table: ----
        if {[regexp -nocase {^Table:\s*(.+)$} $line -> tname]} {
            if {$buffer ne "" && $current_name ne ""} {
                set current_items [ipt_flush_buffer $buffer $current_items]
                set buffer ""
            }
            if {$current_name ne ""} {
                dict set tables $current_name $current_items
            }
            set current_name [string trim $tname]
            set current_items {}
            if {$current_name ni $order} { lappend order $current_name }
            dict set types $current_name Weighted
            continue
        }

        # ---- Commandes de table ----
        if {$current_name ne ""} {
            if {[regexp -nocase {^Type:\s*(.+)$} $line -> v]} {
                dict set types $current_name [string trim $v]; continue }
            if {[regexp -nocase {^Roll:\s*(.+)$} $line -> v]} {
                dict set rolls $current_name [string trim $v]; continue }
            if {[regexp -nocase {^Default:\s*(.*)$} $line -> v]} {
                dict set defaults $current_name [string trim $v]; continue }
            if {[regexp -nocase {^Shuffle:\s*(.+)$} $line -> v]} {
                # Marquer que cette table doit réinitialiser le deck de $v avant son tirage
                lappend current_items [dict create weight -2 text [string trim $v]]
                continue
            }
            if {[regexp -nocase {^EndTable:} $line]} {
                if {$buffer ne ""} {
                    set current_items [ipt_flush_buffer $buffer $current_items]
                    set buffer ""
                }
                dict set tables $current_name $current_items
                set current_name ""
                set current_items {}
                continue
            }
        }

        # ---- Commandes d'en-tête ----
        if {$current_name eq ""} {
            if {[regexp -nocase {^Header:\s*(.*)$}    $line -> v]} { dict set header Header    [string trim $v]; continue }
            if {[regexp -nocase {^Footer:\s*(.*)$}    $line -> v]} { dict set header Footer    [string trim $v]; continue }
            if {[regexp -nocase {^MaxReps:\s*(\d+)$}  $line -> v]} { dict set header MaxReps   $v;               continue }
            if {[regexp -nocase {^Formatting:\s*(.+)$} $line -> v]} { dict set header Formatting [string trim $v]; continue }
            if {[regexp -nocase {^Title:\s*(.*)$}     $line -> v]} { dict set header Title     [string trim $v]; continue }
            if {[regexp -nocase {^Use:\s*(.+)$}         $line -> v]} { lappend use_files [string trim $v]; continue }
            if {[regexp -nocase {^Prompt:\s*(.+)$}    $line -> v]} { lappend prompts [string trim $v]; continue }
            if {[regexp -nocase {^Set:\s*(\w+)\s*=\s*(.*)$} $line -> var val]} {
                lappend global_sets [list $var [string trim $val]]
                continue
            }
            if {[regexp -nocase {^Define:\s*(\w+)\s*=\s*(.*)$} $line -> var val]} {
                lappend defines [list $var [string trim $val]]
                continue
            }
            continue
        }

        # ---- Item de table avec continuation & ----
        if {[string index $line end] eq "&"} {
            set chunk [string trimright [string range $line 0 end-1]]
            if {$buffer eq ""} {
                set buffer $chunk
            } else {
                append buffer " " $chunk
            }
        } else {
            if {$buffer eq ""} {
                set buffer $line
            } else {
                append buffer " " $line
            }
            set current_items [ipt_flush_buffer $buffer $current_items]
            set buffer ""
        }
    }

    # Flush final
    if {$buffer ne "" && $current_name ne ""} {
        set current_items [ipt_flush_buffer $buffer $current_items]
    }
    if {$current_name ne ""} {
        dict set tables $current_name $current_items
    }

    return [dict create \
        header      $header \
        tables      $tables \
        order       $order \
        types       $types \
        rolls       $rolls \
        defaults    $defaults \
        prompts     $prompts \
        global_sets $global_sets \
        use_files   $use_files \
        defines     $defines]
}

proc ipt_flush_buffer {buf items} {
    set buf [string trim $buf]
    if {$buf eq ""} { return $items }

    # Set: en ligne standalone = directive (non un item aléatoire)
    # Elle sera exécutée à chaque appel de la table
    if {[regexp -nocase {^Set:\s*\w+\s*=} $buf]} {
        lappend items [dict create weight -1 text $buf]
        return $items
    }

    set weight 1
    set content $buf
    # Poids pondéré N:texte
    if {[regexp {^(\d+):(.+)$} $buf -> w rest]} {
        set weight [expr {int($w)}]
        set content [string trim $rest]
    }

    lappend items [dict create weight $weight text $content]
    return $items
}

# ============================================================
# TIRAGE PONDÉRÉ
# ============================================================
proc pick_weighted {items} {
    set total 0
    foreach item $items { incr total [dict get $item weight] }
    if {$total == 0} { return "" }

    set r [expr {rand() * $total}]
    set acc 0.0
    foreach item $items {
        set acc [expr {$acc + [dict get $item weight]}]
        if {$r <= $acc} { return [dict get $item text] }
    }
    return [dict get [lindex $items end] text]
}

# ============================================================
# ÉVALUATEUR D'EXPRESSIONS {expr}
# ============================================================

# Expand toutes les accolades {expr} dans une chaîne
proc expand_braces {s vars_var} {
    upvar $vars_var vars
    set result ""
    set i 0
    set len [string length $s]
    while {$i < $len} {
        set c [string index $s $i]
        if {$c eq "\{"} {
            # Trouver l'accolade fermante (profondeur 1+)
            set depth 1
            set j [expr {$i + 1}]
            while {$j < $len && $depth > 0} {
                set ch [string index $s $j]
                if {$ch eq "\{"} { incr depth }
                if {$ch eq "\}"} { incr depth -1 }
                incr j
            }
            set expr_ [string range $s [expr {$i+1}] [expr {$j-2}]]
            append result [eval_brace_expr $expr_ vars]
            set i $j
        } else {
            append result $c
            incr i
        }
    }
    return $result
}

# Cherche et évalue un define. Retourne vide si not trouvé.
proc lookup_define {var defines vars_var} {
    upvar $vars_var vars
    foreach def $defines {
        if {[lindex $def 0] eq $var} {
            set expr [lindex $def 1]
            return [eval_brace_expr $expr vars]
        }
    }
    return ""
}

proc eval_brace_expr {e vars_var} {
    upvar $vars_var vars
    set e [string trim $e]

    # {$var}
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

    # {var==expr} affectation silencieuse
    if {[regexp {^(\w+)==(.+)$} $e -> var rhs]} {
        set vars($var) [eval_brace_expr $rhs vars]
        return ""
    }
    # {var=expr} affectation + affichage
    if {[regexp {^(\w+)=(.+)$} $e -> var rhs]} {
        set val [eval_brace_expr $rhs vars]
        set vars($var) $val
        return $val
    }

    # Dé simple NdN (avec modificateur optionnel)
    if {[regexp {^(\d+)[dD](\d+)([-+]\d+)?$} $e -> n d mod]} {
        set total 0
        for {set i 0} {$i < $n} {incr i} {
            incr total [expr {int(rand() * $d) + 1}]
        }
        if {$mod ne ""} { set total [expr "$total $mod"] }
        return $total
    }

    # Variable simple (mot connu)
    if {[regexp {^\w+$} $e]} {
        if {[info exists vars($e)]} {
            return $vars($e)
        }
        # Chercher dans les defines
        if {[info exists vars(__defines)]} {
            set val [lookup_define $e $vars(__defines) vars]
            if {$val ne ""} { return $val }
        }
        return "\[UNDEF:$e\]"
    }

    # Expression mathématique — substituer dés et variables
    set safe $e
    # Substituer {$var} et {var} dans l'expression (formes explicites)
    if {[array size vars] > 0} {
        foreach var [array names vars] {
            set val $vars($var)
            # Remplacer {$var}
            set safe [string map [list "\{\\$$var\}" $val] $safe]
            # Remplacer {var}
            set safe [string map [list "\{${var}\}" $val] $safe]
        }
    }
    # Substituer dés NdN
    set prev2 ""
    while {$safe ne $prev2} {
        set prev2 $safe
        if {[regexp {(\d+)[dD](\d+)([-+]\d+)?} $safe -> n d mod]} {
            set total 0
            for {set i 0} {$i < $n} {incr i} {
                incr total [expr {int(rand() * $d) + 1}]
            }
            if {$mod ne ""} { set total [expr "$total $mod"] }
            regsub {(\d+)[dD](\d+)([-+]\d+)?} $safe $total safe
        }
    }
    # Fonctions SparkPad → Tcl mathfunc
    foreach {sp tc} {
        max   tcl::mathfunc::max
        min   tcl::mathfunc::min
        sqrt  tcl::mathfunc::sqrt
        abs   tcl::mathfunc::abs
        round tcl::mathfunc::round
        floor tcl::mathfunc::floor
        ceil  tcl::mathfunc::ceil
    } {
        regsub -all -nocase "${sp}\\(" $safe "${tc}(" safe
    }
    if {[catch {set result [expr $safe]} err]} {
        return $e
    }
    return $result
}

# ============================================================
# CHOIX INLINE [|opt1|opt2|...]
# ============================================================
proc expand_inline_choices {s} {
    set prev ""
    while {$s ne $prev} {
        set prev $s
        set i 0
        set len [string length $s]
        set result ""
        while {$i < $len} {
            if {$i+1 < $len && [string range $s $i [expr {$i+1}]] eq {[|}} {
                # Trouver ] en tenant compte de l'imbrication
                set depth 1
                set j [expr {$i + 2}]
                while {$j < $len && $depth > 0} {
                    set ch [string index $s $j]
                    if {$ch eq "\["} { incr depth }
                    if {$ch eq "\]"} { incr depth -1 }
                    incr j
                }
                set inner [string range $s [expr {$i+2}] [expr {$j-2}]]
                # Découper par | (hors imbrication)
                set parts {}
                set buf ""
                set d 0
                foreach ch [split $inner ""] {
                    if {$ch eq "\["} { incr d }
                    if {$ch eq "\]"} { incr d -1 }
                    if {$ch eq "|" && $d == 0} {
                        lappend parts $buf
                        set buf ""
                    } else {
                        append buf $ch
                    }
                }
                lappend parts $buf
                set choice [lindex $parts [rand_int [llength $parts]]]
                append result $choice
                set i $j
            } else {
                append result [string index $s $i]
                incr i
            }
        }
        set s $result
    }
    return $s
}

# ============================================================
# FILTRES
# ============================================================
proc apply_filter {text filter_str formatting} {
    set parts [split [string trim $filter_str]]
    set fname [string tolower [lindex $parts 0]]
    set fargs [lrange $parts 1 end]

    switch -- $fname {
        lower      { return [string tolower $text] }
        upper      { return [string toupper $text] }
        proper     {
            set result {}
            foreach w [split $text " "] {
                if {$w eq ""} continue
                lappend result "[string toupper [string index $w 0]][string range $w 1 end]"
            }
            return [join $result " "]
        }
        bold       {
            if {$formatting eq "html"} { return "<b>$text</b>" }
            return [string toupper $text]
        }
        italic     {
            if {$formatting eq "html"} { return "<i>$text</i>" }
            return "*$text*"
        }
        underline  {
            if {$formatting eq "html"} { return "<u>$text</u>" }
            return "\"$text\""
        }
        trim       { return [string trim $text] }
        ltrim      { return [string trimleft $text] }
        rtrim      { return [string trimright $text] }
        length     { return [string length [string trim $text]] }
        reverse    { return [join [lreverse [split $text ""]] ""] }
        left       {
            set n [expr {[lindex $fargs 0] ne "" ? int([lindex $fargs 0]) : 1}]
            return [string range $text 0 [expr {$n-1}]]
        }
        right      {
            set n [expr {[lindex $fargs 0] ne "" ? int([lindex $fargs 0]) : 1}]
            set l [string length $text]
            return [string range $text [expr {$l-$n}] end]
        }
        substr     {
            set start [expr {int([lindex $fargs 0]) - 1}]
            set len   [expr {[lindex $fargs 1] ne "" ? int([lindex $fargs 1]) : 1}]
            if {$len == 0} { return [string range $text $start end] }
            return [string range $text $start [expr {$start+$len-1}]]
        }
        at         {
            set sub [join $fargs " "]
            set pos [string first $sub [string trim $text]]
            return [expr {$pos < 0 ? 0 : $pos+1}]
        }
        replace    {
            set spec [join $fargs " "]
            if {[regexp {^/(.+)/(.*)/$} $spec -> find repl]} {
                regsub -all [string map {\\ \\\\} $find] $text $repl text
            }
            return $text
        }
        +-         -
        plusminus  {
            if {[catch {set n [expr {int($text)}]} err]} { return $text }
            if {$n >= 0} { return "+$n" } else { return $n }
        }
        default    { return $text }
    }
}

# ============================================================
# EXPANSION PRINCIPALE
# ============================================================
proc ipt_expand {s tables_var vars_var {depth 0}} {
    upvar $tables_var tables
    upvar $vars_var vars

    if {$depth > 60} { return $s }

    set prev ""
    while {$s ne $prev} {
        set prev $s
        set s [expand_braces $s vars]
        set s [expand_conditionals $s tables vars $depth]
        set s [expand_inline_choices $s]
        set s [expand_bracket_calls $s tables vars $depth]
    }
    return $s
}

# Conditionnels [if {$x} == val]A[else]B] (format Lua legacy)
proc expand_conditionals {s tables_var vars_var depth} {
    upvar $tables_var tables
    upvar $vars_var vars

    # Format Lua : [if {$x} == val]A[else]B]
    while {[regexp {\[if\s+(.*?)\](.*?)\[else\](.*?)\]} $s -> cond a b]} {
        set var ""
        set val ""
        regexp {\{\$(.+?)\}\s*==\s*(\S+)} $cond -> var val
        set got ""
        if {$var ne "" && [info exists vars($var)]} { set got $vars($var) }
        if {$got eq $val} {
            regsub {\[if\s+(.*?)\](.*?)\[else\](.*?)\]} $s $a s
        } else {
            regsub {\[if\s+(.*?)\](.*?)\[else\](.*?)\]} $s $b s
        }
    }

    # Format SparkPad : [when]cond[do]expr[else]expr2[end]
    foreach {neg pat} {
        1 {\[when not\](.*?)\[do\](.*?)\[else\](.*?)\[end\]}
        0 {\[when\](.*?)\[do\](.*?)\[else\](.*?)\[end\]}
        1 {\[when not\](.*?)\[do\](.*?)\[end\]}
        0 {\[when\](.*?)\[do\](.*?)\[end\]}
    } {
        while {[regexp $pat $s -> cond do_ else_]} {
            set cv [ipt_expand $cond tables vars [expr {$depth+1}]]
            set ev [ipt_eval_cond $cv]
            if {$neg} { set ev [expr {!$ev}] }
            set rep [expr {$ev ? $do_ : (([info exists else_] && $else_ ne "") ? $else_ : "")}]
            regsub $pat $s $rep s
        }
    }

    return $s
}

proc ipt_eval_cond {cond} {
    set cond [string trim $cond]
    if {$cond eq ""} { return 0 }
    foreach op {<> >= <= > < =} {
        if {[regexp "^(.+?)\\s*${op}\\s*(.+?)$" $cond -> lhs rhs]} {
            set lhs [string trim $lhs]
            set rhs [string trim $rhs]
            set num [expr {[string is double -strict $lhs] && [string is double -strict $rhs]}]
            switch -- $op {
                =  { return [expr {$num ? ($lhs == $rhs) : ($lhs eq $rhs)}] }
                <> { return [expr {$num ? ($lhs != $rhs) : ($lhs ne $rhs)}] }
                >  { return [expr {$num ? ($lhs > $rhs)  : ([string compare $lhs $rhs] > 0)}] }
                <  { return [expr {$num ? ($lhs < $rhs)  : ([string compare $lhs $rhs] < 0)}] }
                >= { return [expr {$num ? ($lhs >= $rhs) : ([string compare $lhs $rhs] >= 0)}] }
                <= { return [expr {$num ? ($lhs <= $rhs) : ([string compare $lhs $rhs] <= 0)}] }
            }
        }
    }
    return [expr {$cond ne ""}]
}

# Expand les appels de tables [@...] [#...] [!...]
proc expand_bracket_calls {s tables_var vars_var depth} {
    upvar $tables_var tables
    upvar $vars_var vars

    set result ""
    set i 0
    set len [string length $s]

    while {$i < $len} {
        set c [string index $s $i]

        if {$c ne "\["} {
            append result $c
            incr i
            continue
        }

        # Trouver ] correspondant
        set depth2 1
        set j [expr {$i + 1}]
        while {$j < $len && $depth2 > 0} {
            set ch [string index $s $j]
            if {$ch eq "\["} { incr depth2 }
            if {$ch eq "\]"} { incr depth2 -1 }
            incr j
        }
        set inner [string range $s [expr {$i+1}] [expr {$j-2}]]

        # [| ...] — déjà traité
        if {[string index $inner 0] eq "|"} {
            append result "\[${inner}\]"
            set i $j
            continue
        }

        set tag [string index $inner 0]
        if {$tag in {"@" "#" "!"}} {
            set body [string range $inner 1 end]
            append result [ipt_process_tag $tag $body tables vars $depth]
            set i $j
        } else {
            # Texte littéral avec filtres éventuels
            append result [ipt_process_literal $inner tables vars $depth]
            set i $j
        }
    }
    return $result
}

# Parse et exécute un tag de table
proc ipt_process_tag {tag body tables_var vars_var depth} {
    upvar $tables_var tables
    upvar $vars_var vars

    set formatting [expr {[info exists vars(formatting)] ? $vars(formatting) : "html"}]

    # Extraire les filtres >> f1 >> f2
    set filters {}
    if {[string first ">>" $body] >= 0} {
        set parts [split $body ">>"]
        set body  [string trim [lindex $parts 0]]
        foreach f [lrange $parts 1 end] {
            set ft [string trim $f]
            if {$ft ne ""} { lappend filters $ft }
        }
    }

    # Affectation inline var== ou var=
    set silent     0
    set assign_var ""
    if {[regexp {^(\w+)==(.+)$} $body -> av rest]} {
        set assign_var $av; set silent 1; set body $rest
    } elseif {[regexp {^(\w+)=([^=].*)$} $body -> av rest]} {
        set assign_var $av; set body $rest
    }

    # Pour [#N table] : N = index (1-based), pas répétitions
    # Pour [@N table] et [!N table] : N = nombre de répétitions
    set reps       1
    set pick_index 0   ;# 0 = tirage aléatoire, >0 = index fixe

    if {$tag eq "#"} {
        # Tenter d'extraire un index numérique en début de body
        set expanded_body [ipt_expand $body tables vars [expr {$depth+1}]]
        if {[regexp {^(\d+)\s+(.+)$} $expanded_body -> n rest]} {
            set pick_index $n
            set body $rest
        } else {
            set body $expanded_body
        }
    } else {
        # Tenter d'extraire un nombre de répétitions
        set expanded_n [ipt_expand $body tables vars [expr {$depth+1}]]
        if {[regexp {^(\d+)\s+(.+)$} $expanded_n -> n rest]} {
            set reps $n; set body $rest
        }
        # (sinon body reste tel quel pour l'expansion du nom de table)
    }

    # Paramètres with
    set with_params {}
    if {[regexp -nocase {^(.+?)\s+with\s+(.+)$} $body -> tpart wpart]} {
        set body $tpart
        set with_params [split $wpart ","]
    }

    set tname [string trim $body]
    # Le nom de table peut contenir des expressions (sauf si déjà expansé pour #)
    if {$tag ne "#"} {
        set tname [ipt_expand $tname tables vars [expr {$depth+1}]]
    }

    # Paramètres → variables {$1} {$2} ...
    set pidx 1
    foreach p $with_params {
        set pval [string trim $p]
        set vars($pidx) $pval
        incr pidx
    }

    # Effectuer le(s) tirage(s)
    set results {}
    if {$pick_index > 0} {
        # [#N table] — pick item à l'index N (1-based, sur les vrais items)
        if {[dict exists $tables $tname]} {
            set real {}
            foreach item [dict get $tables $tname] {
                if {[dict get $item weight] > 0} { lappend real $item }
            }
            set idx [expr {$pick_index - 1}]
            if {$idx < [llength $real]} {
                set text [dict get [lindex $real $idx] text]
                lappend results [ipt_expand $text tables vars [expr {$depth+1}]]
            } else {
                lappend results [expr {[dict exists $tables $tname] ? "" : "\[UNKNOWN:$tname\]"}]
            }
        } else {
            lappend results "\[UNKNOWN:$tname\]"
        }
    } elseif {$tag eq "!"} {
        # Deck pick : tirage sans remise — utiliser le pool ::deck_<tname>
        set pool_var "::deck_${tname}"
        if {![info exists $pool_var] || [llength [set $pool_var]] == 0} {
            # Initialiser (ou réinitialiser) le deck depuis la table
            set pool {}
            if {[dict exists $tables $tname]} {
                foreach item [dict get $tables $tname] {
                    if {[dict get $item weight] > 0} {
                        lappend pool [dict get $item text]
                    }
                }
            }
            set $pool_var $pool
        }
        for {set r 0} {$r < $reps} {incr r} {
            set pool [set $pool_var]
            if {[llength $pool] == 0} break
            set idx [rand_int [llength $pool]]
            set picked [lindex $pool $idx]
            set $pool_var [lreplace $pool $idx $idx]
            lappend results [ipt_expand $picked tables vars [expr {$depth+1}]]
        }
    } else {
        for {set r 0} {$r < $reps} {incr r} {
            lappend results [ipt_roll $tag $tname tables vars $depth]
        }
    }

    # Appliquer les filtres
    set out $results
    foreach f $filters {
        set fname [string tolower [lindex [split $f] 0]]
        if {$fname eq "sort"} {
            set out [lsort $out]
        } elseif {$fname in {implode}} {
            set rest [string trim [string range $f [string length "implode"] end]]
            set glue [expr {$rest ne "" ? $rest : ", "}]
            set out [list [join $out $glue]]
        } elseif {$fname eq "each"} {
            set sub [string trim [string range $f 4 end]]
            set new {}
            foreach item $out {
                set vars(1) $item
                lappend new [ipt_roll "@" $sub tables vars $depth]
            }
            set out $new
        } elseif {$fname eq "eachchar"} {
            set sub [string trim [string range $f 8 end]]
            set joined [join $out ""]
            set new {}
            foreach ch [split $joined ""] {
                set vars(1) $ch
                lappend new [ipt_roll "@" $sub tables vars $depth]
            }
            set out [list [join $new ""]]
        } else {
            set joined [join $out " "]
            set out [list [apply_filter $joined $f $formatting]]
        }
    }

    set out [join $out " "]

    if {$assign_var ne ""} {
        set vars($assign_var) $out
        if {$silent} { return "" }
    }
    return $out
}

proc ipt_process_literal {inner tables_var vars_var depth} {
    upvar $tables_var tables
    upvar $vars_var vars

    set formatting [expr {[info exists vars(formatting)] ? $vars(formatting) : "html"}]
    set filters {}
    set text $inner

    if {[string first ">>" $inner] >= 0} {
        set parts [split $inner ">>"]
        set text [string trim [lindex $parts 0]]
        foreach f [lrange $parts 1 end] {
            set ft [string trim $f]
            if {$ft ne ""} { lappend filters $ft }
        }
    }

    set text [ipt_expand $text tables vars [expr {$depth+1}]]
    foreach f $filters {
        set text [apply_filter $text $f $formatting]
    }
    return $text
}

# Tirage sur une table nommée
proc ipt_roll {tag tname tables_var vars_var depth} {
    upvar $tables_var tables
    upvar $vars_var vars

    # Variable déjà fixée ?
    if {[info exists vars($tname)]} { return $vars($tname) }

    if {![dict exists $tables $tname]} {
        return "\[UNKNOWN:$tname\]"
    }

    set items [dict get $tables $tname]
    if {[llength $items] == 0} { return "" }

    # Exécuter les directives (weight=-1 = Set:, weight=-2 = Shuffle:)
    set real_items {}
    foreach item $items {
        set w [dict get $item weight]
        if {$w == -1} {
            set text [dict get $item text]
            if {[regexp -nocase {^Set:\s*(\w+)\s*=\s*(.*)$} $text -> var val]} {
                set vars($var) [ipt_expand $val tables vars [expr {$depth+1}]]
            }
        } elseif {$w == -2} {
            # Shuffle: réinitialise le deck d'une table nommée
            set deck_tname [dict get $item text]
            unset -nocomplain ::deck_${deck_tname}
        } else {
            lappend real_items $item
        }
    }

    if {[llength $real_items] == 0} { return "" }
    set text [pick_weighted $real_items]
    if {$text eq ""} { return "" }

    return [ipt_expand $text tables vars [expr {$depth+1}]]
}

# ============================================================
# GÉNÉRATION
# ============================================================
proc ipt_generate {parsed {rep 1}} {
    set tables [dict get $parsed tables]
    set order  [dict get $parsed order]
    set header [dict get $parsed header]
    set defines [expr {[dict exists $parsed defines] ? [dict get $parsed defines] : {}}]

    if {[llength $order] == 0} { return "Aucune table trouvée." }

    array set vars {}
    set vars(app)        "Sparkwyrd"
    set vars(version)    "1.0"
    set vars(os)         $::tcl_platform(os)
    set vars(date)       [clock format [clock seconds] -format "%d/%m/%Y"]
    set vars(time)       [clock format [clock seconds] -format "%H:%M"]
    set vars(rep)        $rep
    set vars(formatting) [dict get $header Formatting]
    set vars(cli)        ""
    set vars(__defines)  $defines    ;# Stocker les defines pour accès ultérieur

    # Exécuter les Set: globaux (définis avant toute Table:)
    foreach gs [dict get $parsed global_sets] {
        set gvar [lindex $gs 0]
        set gval [lindex $gs 1]
        set vars($gvar) [ipt_expand $gval tables vars 0]
    }

    set start [lindex $order 0]
    if {![dict exists $tables $start]} { return "Table introuvable : $start" }

    # Déléguer entièrement à ipt_roll (gère les directives Set:)
    set result [ipt_roll "@" $start tables vars 0]

    # Nettoyage des caractères spéciaux (\n \t \z \_)
    # "\\n" = la séquence littérale backslash+n dans la chaîne
    set result [string map [list "\\n" "\n" "\\t" "\t" "\\z" "" "\\_" " "] $result]

    # Résoudre \a (a/an) — heuristique anglaise
    set result [regsub -all {\\a\s+([AEIOUaeiou])} $result {an \1}]
    set result [regsub -all {\\a\s+(\S)} $result {a \1}]

    # Nettoyer les & résiduels de continuation
    set result [regsub -all { *& *} $result " "]
    # Réduire les espaces multiples sur chaque ligne (mais pas les sauts de ligne)
    set lines {}
    foreach line [split $result "\n"] {
        lappend lines [regsub -all { {2,}} $line " "]
    }
    set result [join $lines "\n"]
    # Supprimer espace avant ponctuation
    set result [regsub -all { ([,.:;!?])} $result {\1}]
    set result [string trim $result]

    return $result
}

# === cli ===
# Sparkwyrd CLI — command-line .ipt generator


# ============================================================
proc usage {} {
    set name [file tail [info script]]
    puts stderr "Sparkwyrd 1.0 — Inspiration Pad Pro compatible generator

Usage:
  $name \[--gui\] \[file.ipt\]              Start GUI (default)
  $name --cli \[options\] file.ipt         Command-line mode

Mode:
  --gui           Open graphical interface (default when no CLI flags given)
  --cli           Force command-line mode

CLI options:
  -n <count>      Number of generations  (default: 1)
  -t <table>      Start from named table (default: first table in file)
  --html          Keep HTML tags in output (default: tags are stripped)
  --sep <string>  Separator between outputs (default: empty line)
  --list          List all table names in the file, then exit
  --version       Show version and exit
  --help          Show this help and exit

Notes:
  HTML tags are stripped by default in CLI mode. Use --html to preserve them.
  GUI mode is selected automatically when no CLI flags are present.

Examples:
  $name                               open GUI
  $name --gui my_generator.ipt        open GUI with file
  $name --cli demo.ipt                one generation, plain text
  $name --cli -n 5 names.ipt          five generations
  $name --cli --html -n 2 adv.ipt     keep HTML tags
  $name --cli -t treasure loot.ipt    start from specific table
  $name --cli --list demo.ipt         list tables"
    exit 1
}

proc show_version {} {
    puts "Sparkwyrd CLI 1.0"
    exit 0
}

# Strip HTML tags; optionally decode common entities
proc strip_html {text} {
    # Remove tags
    set text [regsub -all {<[^>]+>} $text ""]
    # Decode entities
    set text [string map {
        &amp;  &   &lt;  <   &gt;  >
        &quot; \"  &apos; '  &nbsp; { }
    } $text]
    return $text
}

# ============================================================
# Entry point — wrapped in proc so the merged build controls when it runs.
# ============================================================
proc cli_main {} {
    global argv

    set opt_n    1
    set opt_t    ""
    set opt_html 0       ;# 0 = strip HTML (default), 1 = keep raw HTML
    set opt_sep  "\n"
    set opt_list 0
    set ipt_file ""

    set i 0
    while {$i < [llength $argv]} {
        set arg [lindex $argv $i]
        switch -- $arg {
            -n        { incr i; set opt_n [lindex $argv $i]
                        if {![string is integer -strict $opt_n] || $opt_n < 1} {
                            puts stderr "Error: -n requires a positive integer"
                            exit 1
                        } }
            -t        { incr i; set opt_t [lindex $argv $i] }
            --html    { set opt_html 1 }
            --sep     { incr i; set opt_sep [lindex $argv $i] }
            --list    { set opt_list 1 }
            --version { show_version }
            --help    { usage }
            default   {
                if {[string match "-*" $arg]} {
                    puts stderr "Unknown option: $arg"
                    usage
                }
                if {$ipt_file ne ""} {
                    puts stderr "Error: multiple files specified"
                    usage
                }
                set ipt_file $arg
            }
        }
        incr i
    }

    if {$ipt_file eq ""} { usage }

    if {![file exists $ipt_file]} {
        puts stderr "Error: file not found: $ipt_file"
        exit 1
    }

    if {[catch {set parsed [parse_ipt $ipt_file]} err]} {
        puts stderr "Error parsing '$ipt_file': $err"
        exit 1
    }

    set order [dict get $parsed order]

    if {$opt_list} {
        set h [dict get $parsed header]
        set hd [strip_html [dict get $h Header]]
        if {$hd ne ""} { puts "Header : $hd" }
        set mr [dict get $h MaxReps]
        if {$mr > 0}   { puts "MaxReps: $mr" }
        puts "\nTables ([llength $order]):"
        foreach t $order { puts "  • $t" }
        exit 0
    }

    if {$opt_t ne ""} {
        if {$opt_t ni $order} {
            puts stderr "Error: table '$opt_t' not found."
            puts stderr "Available: [join $order {, }]"
            exit 1
        }
        set new_order [list $opt_t]
        foreach t $order { if {$t ne $opt_t} { lappend new_order $t } }
        dict set parsed order $new_order
    }

    set mr [dict get [dict get $parsed header] MaxReps]
    if {$mr > 0 && $opt_n > $mr} { set opt_n $mr }

    for {set i 1} {$i <= $opt_n} {incr i} {
        if {[catch {set result [ipt_generate $parsed $i]} err]} {
            puts stderr "Error generating repetition $i: $err"
            exit 1
        }
        if {!$opt_html} { set result [strip_html $result] }
        puts $result
        if {$i < $opt_n} { puts [expr {$opt_sep ne "\n" ? $opt_sep : ""}] }
    }
}

if {![info exists ::sparkwyrd_combined]} { cli_main }

# === gui ===
# Sparkwyrd — Tk GUI


# ============================================================
# GLOBAL STATE
# ============================================================
set ::current_parsed {}
set ::current_file   ""
set ::reps_count     1
set ::status_msg     "Welcome to Sparkwyrd — open an .ipt file to begin"
set ::current_theme  "sepia"

# ============================================================
# THEME PALETTES
# ============================================================
array set ::themes {}

set ::themes(light) {
    bg         #f0f0f0
    bg2        #fafafa
    bg_tb      #ececec
    fg         #1a1a1a
    fg2        #666666
    fg_link    #0055cc
    sep        #cccccc
    out_bg     #ffffff
    out_fg     #111111
    out_title  #1a1a2e
    out_sep    #bbbbbb
    out_h1     #1a1a2e
    out_h2     #2a2a6e
    out_h3     #3a3a7e
    out_code_bg #f0f0f0
    btn_bg     #dcdcdc
    btn_fg     #1a1a1a
    btn_go_bg  #3a7d44
    btn_go_fg  #ffffff
    sel_bg     #3a7d44
    sel_fg     #ffffff
}

set ::themes(dark) {
    bg         #2b2b2b
    bg2        #242424
    bg_tb      #333333
    fg         #e0e0e0
    fg2        #888888
    fg_link    #6699ff
    sep        #444444
    out_bg     #1e1e1e
    out_fg     #d4d4d4
    out_title  #c8b97a
    out_sep    #444444
    out_h1     #c8b97a
    out_h2     #9ab8d8
    out_h3     #88aa88
    out_code_bg #2a2a2a
    btn_bg     #3c3c3c
    btn_fg     #e0e0e0
    btn_go_bg  #2e6636
    btn_go_fg  #ffffff
    sel_bg     #264f78
    sel_fg     #ffffff
}

set ::themes(sepia) {
    bg         #f5efe0
    bg2        #faf6ee
    bg_tb      #ede5d0
    fg         #3b2e1e
    fg2        #7a6248
    fg_link    #8b4513
    sep        #c8b89a
    out_bg     #fdf6e3
    out_fg     #3b2e1e
    out_title  #5c3d1e
    out_sep    #c8b89a
    out_h1     #5c3d1e
    out_h2     #7a4f28
    out_h3     #8b5e32
    out_code_bg #ede5d0
    btn_bg     #d8c9a8
    btn_fg     #3b2e1e
    btn_go_bg  #7a4f28
    btn_go_fg  #fdf6e3
    sel_bg     #c8a878
    sel_fg     #1a0a00
}

proc T {key} {
    return [dict get $::themes($::current_theme) $key]
}

# ============================================================
# THEME APPLICATION
# ============================================================
proc apply_theme {{theme ""}} {
    if {$theme ne ""} { set ::current_theme $theme }

    # Tk option database — applies to future widgets
    option add *Background          [T bg]      interactive
    option add *Foreground          [T fg]      interactive
    option add *Button.Background   [T btn_bg]  interactive
    option add *Button.Foreground   [T btn_fg]  interactive
    option add *Label.Background    [T bg]      interactive
    option add *Label.Foreground    [T fg]      interactive
    option add *Entry.Background    [T out_bg]  interactive
    option add *Entry.Foreground    [T out_fg]  interactive
    option add *Spinbox.Background  [T out_bg]  interactive
    option add *Spinbox.Foreground  [T out_fg]  interactive
    option add *selectBackground    [T sel_bg]  interactive
    option add *selectForeground    [T sel_fg]  interactive

    if {![winfo exists .tb]} return

    # Toolbar
    .tb configure -bg [T bg_tb]
    foreach w {.tb.open .tb.clr .tb.lrep .tb.theme_lbl} {
        catch { $w configure -bg [T bg_tb] -fg [T fg] -activebackground [T bg] }
    }
    catch { .tb.theme_mb configure -bg [T bg_tb] -fg [T fg] \
                -activebackground [T bg] -activeforeground [T fg] }
    .tb.sep1 configure -bg [T sep]
    .tb.go configure -bg [T btn_go_bg] -fg [T btn_go_fg] \
        -activebackground [T btn_go_bg]
    .tb.reps configure -bg [T out_bg] -fg [T out_fg] \
        -insertbackground [T out_fg]

    # Left panel
    .left configure -bg [T bg2]
    foreach w {.left.t1 .left.t2 .left.t3 .left.hd .left.mr} {
        catch { $w configure -bg [T bg2] -fg [T fg] }
    }
    .left.fname configure -bg [T bg2] -fg [T fg_link]
    .left.sep  configure -bg [T sep]
    .left.sep2 configure -bg [T sep]
    .left.tables configure -bg [T bg2] -fg [T fg2] \
        -selectbackground [T sel_bg] -selectforeground [T sel_fg]
    .left.sb configure -bg [T bg2] -troughcolor [T bg]

    # Output area
    .right configure -bg [T out_bg]
    .right.nb.gen.out configure -bg [T out_bg] -fg [T out_fg] \
        -insertbackground [T out_fg] \
        -selectbackground [T sel_bg] -selectforeground [T sel_fg]
    .right.nb.gen.sb configure -bg [T bg] -troughcolor [T bg2]

    # Text widget tags
    .right.nb.gen.out tag configure ttitle \
        -font {Georgia 15 bold} -foreground [T out_title] -spacing3 4
    .right.nb.gen.out tag configure tsep \
        -foreground [T out_sep]
    .right.nb.gen.out tag configure tbody \
        -font {Georgia 12} -foreground [T out_fg] -spacing1 2 -spacing3 2
    .right.nb.gen.out tag configure tbold \
        -font {Georgia 12 bold} -foreground [T out_fg]
    .right.nb.gen.out tag configure titalic \
        -font {Georgia 12 italic} -foreground [T out_fg]
    .right.nb.gen.out tag configure tunderline \
        -font {Georgia 12} -underline 1 -foreground [T out_fg]
    .right.nb.gen.out tag configure tbold_italic \
        -font {Georgia 12 bold italic} -foreground [T out_fg]
    .right.nb.gen.out tag configure th1 \
        -font {Georgia 16 bold} -foreground [T out_h1] -spacing3 6
    .right.nb.gen.out tag configure th2 \
        -font {Georgia 14 bold} -foreground [T out_h2] -spacing3 4
    .right.nb.gen.out tag configure th3 \
        -font {Georgia 13 bold} -foreground [T out_h3] -spacing3 2
    .right.nb.gen.out tag configure tcode \
        -font {TkFixedFont 11} -foreground [T out_fg] \
        -background [T out_code_bg]

    # Editor theme
    editor_apply_theme

    # Status bar
    .st configure -bg [T bg_tb]
    .st.msg configure -bg [T bg_tb] -fg [T fg2]

    .pw configure -bg [T sep]
}

# ============================================================
# UI CONSTRUCTION
# ============================================================
proc build_ui {} {
    wm title . "Sparkwyrd"
    wm geometry . "920x620"
    wm minsize . 640 400

    # ---- Toolbar ----
    frame .tb -relief flat -bd 0
    pack .tb -fill x -side top

    button .tb.open -text "Open..." -command cmd_open \
        -relief flat -padx 10 -pady 5 -cursor hand2
    frame .tb.sep1 -width 1
    label  .tb.lrep -text "Reps:"
    spinbox .tb.reps -from 1 -to 999 -width 4 \
        -textvariable ::reps_count \
        -validate key -validatecommand {string is integer %P}
    button .tb.go -text "  Go" -command cmd_generate \
        -relief flat -padx 14 -pady 5 \
        -font {TkDefaultFont 10 bold} -cursor hand2
    button .tb.clr -text "Clear" -command cmd_clear \
        -relief flat -padx 10 -pady 5 -cursor hand2

    # Theme selector (right side)
    label .tb.theme_lbl -text "Theme:"
    menubutton .tb.theme_mb -textvariable ::current_theme \
        -relief raised -padx 8 -pady 4 -width 8 -cursor hand2
    menu .tb.theme_mb.m -tearoff 0
    foreach th {light dark sepia} {
        .tb.theme_mb.m add command -label $th \
            -command [list apply_theme $th]
    }
    .tb.theme_mb configure -menu .tb.theme_mb.m

    pack .tb.open  -side left -padx {6 2} -pady 4
    pack .tb.sep1  -side left -padx 4 -pady 4 -fill y
    pack .tb.lrep  -side left -padx {4 2} -pady 4
    pack .tb.reps  -side left -padx 2 -pady 4
    pack .tb.go    -side left -padx 6 -pady 4
    pack .tb.clr   -side left -padx 2 -pady 4
    pack .tb.theme_mb  -side right -padx 6 -pady 4
    pack .tb.theme_lbl -side right -padx {4 0} -pady 4

    frame .tb_sep -height 1
    pack .tb_sep -fill x -side top

    # ---- Main area ----
    panedwindow .pw -orient horizontal -sashwidth 5 -sashrelief flat
    pack .pw -fill both -expand 1

    # Left panel
    frame .left -width 210
    pack propagate .left 0

    label .left.t1 -text "Active file" \
        -font {TkDefaultFont 9 bold} -anchor w
    label .left.fname -textvariable ::ui_fname \
        -wraplength 195 -justify left -anchor w
    frame .left.sep -height 1
    label .left.t2 -text "Header" \
        -font {TkDefaultFont 9 bold} -anchor w
    label .left.hd -textvariable ::ui_header \
        -wraplength 195 -justify left -anchor w
    label .left.mr -textvariable ::ui_maxreps \
        -wraplength 195 -justify left -anchor w
    frame .left.sep2 -height 1
    label .left.t3 -text "Tables" \
        -font {TkDefaultFont 9 bold} -anchor w
    text .left.tables -width 22 -height 14 \
        -state disabled -relief flat \
        -font {TkFixedFont 9}
    scrollbar .left.sb -command {.left.tables yview} -width 8
    .left.tables configure -yscrollcommand {.left.sb set}

    # Bind click on table name to jump to it in editor
    bind .left.tables <ButtonRelease-1> {
        set idx [.left.tables index @%x,%y]
        set line [.left.tables get "$idx linestart" "$idx lineend"]
        set name [string trim $line "• \t"]
        if {$name ne ""} {
            editor_goto_table $name
        }
    }

    grid .left.t1    -row 0 -column 0 -columnspan 2 -sticky ew -padx 8 -pady {8 0}
    grid .left.fname -row 1 -column 0 -columnspan 2 -sticky ew -padx 8 -pady {0 4}
    grid .left.sep   -row 2 -column 0 -columnspan 2 -sticky ew
    grid .left.t2    -row 3 -column 0 -columnspan 2 -sticky ew -padx 8 -pady {6 0}
    grid .left.hd    -row 4 -column 0 -columnspan 2 -sticky ew -padx 8
    grid .left.mr    -row 5 -column 0 -columnspan 2 -sticky ew -padx 8
    grid .left.sep2  -row 6 -column 0 -columnspan 2 -sticky ew -pady 4
    grid .left.t3    -row 7 -column 0 -columnspan 2 -sticky ew -padx 8 -pady {0 2}
    grid .left.tables -row 8 -column 0 -sticky nsew -padx {8 0}
    grid .left.sb     -row 8 -column 1 -sticky ns
    grid columnconfigure .left 0 -weight 1
    grid rowconfigure    .left 8 -weight 1

    # Right panel — notebook with Générer and Éditer tabs
    frame .right

    ttk::notebook .right.nb
    frame .right.nb.gen
    .right.nb add .right.nb.gen -text "Générer"
    pack .right.nb -fill both -expand 1

    text .right.nb.gen.out \
        -wrap word \
        -font {Georgia 12} \
        -state disabled \
        -relief flat \
        -bd 0 \
        -yscrollcommand {.right.nb.gen.sb set} \
        -padx 16 -pady 12
    scrollbar .right.nb.gen.sb -command {.right.nb.gen.out yview}
    pack .right.nb.gen.sb  -side right -fill y
    pack .right.nb.gen.out -fill both  -expand 1

    # Editor tab created by editor_init
    editor_init .right.nb

    .pw add .left  -minsize 180
    .pw add .right -minsize 300

    # ---- Status bar ----
    frame .st -relief flat -bd 0
    pack .st -fill x -side bottom
    frame .st.line -height 1
    pack .st.line -fill x
    label .st.msg -textvariable ::status_msg \
        -anchor w -font {TkDefaultFont 9}
    pack .st.msg -fill x -padx 8 -pady 2

    # ---- Key bindings ----
    bind . <F5>        cmd_generate
    bind . <Control-o> cmd_open

    # ---- Init ----
    set ::ui_fname   "(no file)"
    set ::ui_header  ""
    set ::ui_maxreps ""

    apply_theme $::current_theme

    # Auto-load demo.ipt if present (in project root, not src/)
    set demo [file join $::script_dir demo.ipt]
    if {[file exists $demo]} {
        after 100 [list cmd_load_file $demo]
    }
}

# ============================================================
# HTML → text widget parser
# ============================================================
proc html_current_tag {base active_var} {
    upvar $active_var active
    if {$active(h1)}   { return th1 }
    if {$active(h2)}   { return th2 }
    if {$active(h3)}   { return th3 }
    if {$active(code)} { return tcode }
    if {$active(b) && $active(i)} { return tbold_italic }
    if {$active(b)}    { return tbold }
    if {$active(i)}    { return titalic }
    if {$active(u)}    { return tunderline }
    return $base
}

proc html_insert {w html base_tag} {
    array set active {b 0 i 0 u 0 h1 0 h2 0 h3 0 code 0}
    set pos 0
    set len [string length $html]
    while {$pos < $len} {
        set lt [string first "<" $html $pos]
        if {$lt < 0} {
            set val [string range $html $pos end]
            set val [string map {&amp; & &lt; < &gt; > &quot; \" &apos; ' &nbsp; { }} $val]
            $w insert end $val [html_current_tag $base_tag active]
            break
        }
        if {$lt > $pos} {
            set val [string range $html $pos [expr {$lt-1}]]
            set val [string map {&amp; & &lt; < &gt; > &quot; \" &apos; ' &nbsp; { }} $val]
            $w insert end $val [html_current_tag $base_tag active]
        }
        set gt [string first ">" $html $lt]
        if {$gt < 0} {
            $w insert end [string range $html $lt end] [html_current_tag $base_tag active]
            break
        }
        set tag_name [string tolower [lindex [split [string trim [string range $html [expr {$lt+1}] [expr {$gt-1}]]]] 0]]
        switch -- $tag_name {
            b - strong          { set active(b)  1 }
            /b - /strong        { set active(b)  0 }
            i - em              { set active(i)  1 }
            /i - /em            { set active(i)  0 }
            u                   { set active(u)  1 }
            /u                  { set active(u)  0 }
            h1                  { set active(h1) 1 }
            /h1                 { set active(h1) 0; $w insert end "\n" th1 }
            h2                  { set active(h2) 1 }
            /h2                 { set active(h2) 0; $w insert end "\n" th2 }
            h3                  { set active(h3) 1 }
            /h3                 { set active(h3) 0; $w insert end "\n" th3 }
            code - tt           { set active(code) 1 }
            /code - /tt         { set active(code) 0 }
            br - {br/} - {br /} { $w insert end "\n" $base_tag }
            p                   { $w insert end "\n" $base_tag }
            /p                  { $w insert end "\n" $base_tag }
            hr                  { $w insert end "─────────────────────────────────\n" tsep }
            default             {}
        }
        set pos [expr {$gt+1}]
    }
}

# ============================================================
# COMMANDS
# ============================================================
proc cmd_open {} {
    set f [tk_getOpenFile \
        -title "Open a Sparkwyrd generator" \
        -filetypes {
            {"Sparkwyrd generators" {.ipt}}
            {"All files"            {*}}
        } \
        -initialdir $::script_dir]
    if {$f ne ""} { cmd_load_file $f }
}

proc cmd_load_file {path} {
    set ::status_msg "Loading [file tail $path]..."
    update idletasks

    if {[catch {set ::current_parsed [parse_ipt $path]} err]} {
        set ::status_msg "Error: $err"
        tk_messageBox -type ok -icon error \
            -title "Load error" \
            -message "Cannot read file:\n$err"
        return
    }

    set ::current_file $path
    set h     [dict get $::current_parsed header]
    set order [dict get $::current_parsed order]

    set hd_clean [regsub -all {<[^>]+>} [dict get $h Header] ""]
    set mr [dict get $h MaxReps]

    set ::ui_fname   [file tail $path]
    set ::ui_header  $hd_clean
    set ::ui_maxreps [expr {$mr > 0 ? "MaxReps: $mr" : ""}]

    if {$mr > 0 && $::reps_count > $mr} { set ::reps_count $mr }

    .left.tables configure -state normal
    .left.tables delete 1.0 end
    foreach t $order {
        .left.tables insert end "• $t\n"
    }
    .left.tables configure -state disabled

    set n [llength $order]
    set suffix [expr {$n > 1 ? "s" : ""}]
    set ::status_msg "Loaded: [file tail $path] — $n table${suffix}"

    # Load file into editor
    if {$::current_file ne ""} { editor_load $::current_file }

    cmd_generate
}

proc cmd_generate {} {
    if {$::current_parsed eq {}} {
        set ::status_msg "No file loaded — use Open"
        return
    }

    set h  [dict get $::current_parsed header]
    set mr [dict get $h MaxReps]
    set n  $::reps_count
    if {$mr > 0 && $n > $mr} { set n $mr }

    .right.nb.gen.out configure -state normal
    .right.nb.gen.out delete 1.0 end

    set hd_raw [dict get $h Header]
    if {$hd_raw ne ""} {
        html_insert .right.nb.gen.out $hd_raw ttitle
        .right.nb.gen.out insert end "\n─────────────────────────────────\n" tsep
    }

    for {set i 1} {$i <= $n} {incr i} {
        if {[catch {set res [ipt_generate $::current_parsed $i]} err]} {
            set res "  Error: $err"
        }
        html_insert .right.nb.gen.out $res tbody
        .right.nb.gen.out insert end "\n" tbody

        if {$i < $n} {
            .right.nb.gen.out insert end "─────────────────────────────────\n" tsep
        }
    }

    set ft [dict get $h Footer]
    if {$ft ne ""} {
        .right.nb.gen.out insert end "─────────────────────────────────\n" tsep
        html_insert .right.nb.gen.out $ft tsep
        .right.nb.gen.out insert end "\n" tsep
    }

    .right.nb.gen.out configure -state disabled
    .right.nb.gen.out see 1.0
    set plural [expr {$n > 1 ? "s" : ""}]
    set ::status_msg "Generated ($n rep${plural}) — [clock format [clock seconds] -format {%H:%M:%S}]"
}

proc cmd_clear {} {
    .right.nb.gen.out configure -state normal
    .right.nb.gen.out delete 1.0 end
    .right.nb.gen.out configure -state disabled
    set ::status_msg "Output cleared."
}

# ============================================================
# LAUNCH — wrapped in proc so the merged build controls when it runs.
# ============================================================
proc gui_main {} {
    package require Tk
    build_ui
    if {[llength $::argv] > 0 && [file exists [lindex $::argv 0]]} {
        after 150 [list cmd_load_file [lindex $::argv 0]]
    }
}

if {![info exists ::sparkwyrd_combined]} { gui_main }

# === editor ===
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

# === main ===
# Sparkwyrd — entry-point dispatcher (included last by the Makefile build)
#
# Mode selection:
#   (no args)          → print quick usage hint and exit (safe for tab completion)
#   --gui [file.ipt]   → launch GUI
#   --cli [options]    → CLI mode
#   -n / -t / --html … → auto-select CLI mode (recognised CLI flags)
#   file.ipt only      → GUI mode (open file)

proc sparkwyrd_dispatch {} {
    global argv

    set cli_flags {-n -t --html --sep --list --version --help}
    set mode      ""
    set rest      {}

    foreach arg $argv {
        switch -- $arg {
            --gui   { set mode gui }
            --cli   { set mode cli }
            default { lappend rest $arg }
        }
    }
    set argv $rest

    # No arguments at all: default to GUI mode
    if {$mode eq "" && [llength $rest] == 0} {
        set mode gui
    }

    # Auto-detect from remaining args when no explicit --gui/--cli
    if {$mode eq ""} {
        set mode gui
        foreach arg $rest {
            if {$arg in $cli_flags || [string match "-*" $arg]} {
                set mode cli
                break
            }
        }
    }

    if {$mode eq "gui"} {
        if {[catch {gui_main} err]} {
            puts stderr "Cannot start GUI: $err"
            puts stderr "Try: [file tail [info script]] --cli \[options\] file.ipt"
            exit 1
        }
    } else {
        cli_main
    }
}

sparkwyrd_dispatch
