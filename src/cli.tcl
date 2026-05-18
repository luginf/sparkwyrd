#!/usr/bin/env tclsh
# Sparkwyrd CLI — command-line .ipt generator

set script_dir [file normalize [file dirname [info script]]]
source [file join $script_dir engine.tcl]

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
