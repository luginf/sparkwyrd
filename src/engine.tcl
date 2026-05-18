#!/usr/bin/env tclsh
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
